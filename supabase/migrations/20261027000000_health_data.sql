CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL UNIQUE,
  first_name text NOT NULL CHECK (length(trim(first_name)) BETWEEN 1 AND 100),
  last_name text NOT NULL CHECK (length(trim(last_name)) BETWEEN 1 AND 150),
  date_of_birth date NOT NULL CHECK (date_of_birth <= CURRENT_DATE),
  chronic_conditions text[] NOT NULL DEFAULT '{}',
  other_chronic_condition text
    CHECK (
      other_chronic_condition IS NULL
      OR length(trim(other_chronic_condition)) BETWEEN 1 AND 150
    ),
  role text NOT NULL DEFAULT 'patient'
    CHECK (role IN ('patient', 'doctor', 'admin')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.doctor_patient_assignments (
  doctor_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  patient_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (doctor_uid, patient_uid),
  CHECK (doctor_uid <> patient_uid)
);

CREATE INDEX doctor_patient_assignments_patient_idx
  ON public.doctor_patient_assignments(patient_uid);

CREATE TABLE public.equipment_reports (
  id text PRIMARY KEY DEFAULT
    ('REP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
  owner_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  equipment text NOT NULL CHECK (length(trim(equipment)) BETWEEN 1 AND 100),
  description text NOT NULL CHECK (length(trim(description)) BETWEEN 1 AND 500),
  priority text NOT NULL CHECK (priority IN ('Baja', 'Media', 'Alta')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX equipment_reports_owner_created_idx
  ON public.equipment_reports(owner_uid, created_at DESC);

CREATE TABLE public.measurements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reading_at timestamptz NOT NULL,
  source text NOT NULL CHECK (source IN ('wear_os_sensor', 'ble_hr')),
  device_name text NOT NULL CHECK (length(trim(device_name)) BETWEEN 1 AND 100),
  heart_rate_bpm smallint NOT NULL CHECK (heart_rate_bpm BETWEEN 30 AND 220),
  oxygen_saturation_percent smallint
    CHECK (oxygen_saturation_percent BETWEEN 50 AND 100),
  body_temperature_celsius numeric(4, 1)
    CHECK (body_temperature_celsius BETWEEN 25 AND 45),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX measurements_owner_reading_idx
  ON public.measurements(owner_uid, reading_at DESC);

CREATE TABLE public.medication_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  medication_name text NOT NULL
    CHECK (length(trim(medication_name)) BETWEEN 1 AND 100),
  dose text CHECK (dose IS NULL OR length(trim(dose)) <= 100),
  interval_hours smallint NOT NULL CHECK (interval_hours IN (4, 6, 8, 12, 24)),
  first_dose_time time NOT NULL,
  timezone_name text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX medication_reminders_owner_idx
  ON public.medication_reminders(owner_uid, enabled);

CREATE TABLE public.measurement_reminder_settings (
  owner_uid uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  interval_hours smallint NOT NULL DEFAULT 24
    CHECK (interval_hours IN (4, 6, 8, 12, 24)),
  first_measurement_time time NOT NULL DEFAULT '09:00',
  timezone_name text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.is_current_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_assigned_clinician(target_patient uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.doctor_patient_assignments a
    JOIN public.profiles clinician ON clinician.id = a.doctor_uid
    WHERE a.patient_uid = target_patient
      AND a.doctor_uid = (SELECT auth.uid())
      AND clinician.role = 'doctor'
  );
$$;

CREATE OR REPLACE FUNCTION public.create_profile_for_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    first_name,
    last_name,
    date_of_birth,
    chronic_conditions,
    other_chronic_condition
  )
  VALUES (
    NEW.id,
    NEW.email,
    trim(NEW.raw_user_meta_data ->> 'first_name'),
    trim(NEW.raw_user_meta_data ->> 'last_name'),
    (NEW.raw_user_meta_data ->> 'date_of_birth')::date,
    ARRAY(
      SELECT jsonb_array_elements_text(
        COALESCE(NEW.raw_user_meta_data -> 'chronic_conditions', '[]'::jsonb)
      )
    ),
    NULLIF(trim(NEW.raw_user_meta_data ->> 'other_chronic_condition'), '')
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_profile_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles SET email = NEW.email WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_unauthorized_role_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role
    AND NOT public.is_current_admin()
    AND session_user NOT IN ('postgres', 'supabase_admin')
    AND COALESCE(current_setting('request.jwt.claim.role', true), '')
      NOT IN ('', 'service_role') THEN
    RAISE EXCEPTION 'Only an administrator can change profile roles.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_doctor_assignments(
  target_doctor_uid uuid,
  target_patient_uids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  unique_patient_uids uuid[];
  valid_patient_count integer;
BEGIN
  IF NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Only an administrator can manage care assignments.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = target_doctor_uid AND role = 'doctor'
  ) THEN
    RAISE EXCEPTION 'The selected clinician is not a doctor.';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT patient_uid), ARRAY[]::uuid[])
  INTO unique_patient_uids
  FROM unnest(COALESCE(target_patient_uids, ARRAY[]::uuid[]))
    AS values_table(patient_uid);

  IF cardinality(unique_patient_uids) > 30 THEN
    RAISE EXCEPTION 'A doctor can be assigned at most 30 patients.';
  END IF;

  SELECT count(*) INTO valid_patient_count
  FROM public.profiles
  WHERE id = ANY(unique_patient_uids) AND role = 'patient';
  IF valid_patient_count <> cardinality(unique_patient_uids) THEN
    RAISE EXCEPTION 'One or more selected users are not patients.';
  END IF;

  DELETE FROM public.doctor_patient_assignments
  WHERE doctor_uid = target_doctor_uid;
  INSERT INTO public.doctor_patient_assignments (doctor_uid, patient_uid)
  SELECT target_doctor_uid, patient_uid
  FROM unnest(unique_patient_uids) AS values_table(patient_uid);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_for_new_user();

DROP TRIGGER IF EXISTS on_auth_user_email_updated ON auth.users;
CREATE TRIGGER on_auth_user_email_updated
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  WHEN (OLD.email IS DISTINCT FROM NEW.email)
  EXECUTE FUNCTION public.sync_profile_email();

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS profiles_prevent_unauthorized_role_change ON public.profiles;
CREATE TRIGGER profiles_prevent_unauthorized_role_change
  BEFORE UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_unauthorized_role_change();

DROP TRIGGER IF EXISTS equipment_reports_set_updated_at ON public.equipment_reports;
CREATE TRIGGER equipment_reports_set_updated_at
  BEFORE UPDATE ON public.equipment_reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS medication_reminders_set_updated_at ON public.medication_reminders;
CREATE TRIGGER medication_reminders_set_updated_at
  BEFORE UPDATE ON public.medication_reminders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctor_patient_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipment_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medication_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.measurement_reminder_settings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (first_name, last_name, date_of_birth, chronic_conditions, other_chronic_condition)
  ON public.profiles TO authenticated;
GRANT UPDATE (role) ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.doctor_patient_assignments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.equipment_reports TO authenticated;
GRANT SELECT, INSERT ON public.measurements TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.medication_reminders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.measurement_reminder_settings TO authenticated;

DROP POLICY IF EXISTS profiles_read_self_or_care_team ON public.profiles;
CREATE POLICY profiles_read_self_or_care_team ON public.profiles
  FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR public.is_current_admin() OR public.is_assigned_clinician(id));

DROP POLICY IF EXISTS profiles_update_self ON public.profiles;
CREATE POLICY profiles_update_self ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

DROP POLICY IF EXISTS profiles_update_role_admin ON public.profiles;
CREATE POLICY profiles_update_role_admin ON public.profiles
  FOR UPDATE TO authenticated
  USING (public.is_current_admin() AND id <> (SELECT auth.uid()))
  WITH CHECK (public.is_current_admin() AND id <> (SELECT auth.uid()));

DROP POLICY IF EXISTS assignments_read_related_or_admin ON public.doctor_patient_assignments;
CREATE POLICY assignments_read_related_or_admin ON public.doctor_patient_assignments
  FOR SELECT TO authenticated
  USING (
    doctor_uid = (SELECT auth.uid())
    OR patient_uid = (SELECT auth.uid())
    OR public.is_current_admin()
  );

DROP POLICY IF EXISTS assignments_manage_admin ON public.doctor_patient_assignments;
CREATE POLICY assignments_manage_admin ON public.doctor_patient_assignments
  FOR ALL TO authenticated
  USING (public.is_current_admin())
  WITH CHECK (public.is_current_admin());

DROP POLICY IF EXISTS reports_read_owner_clinician_admin ON public.equipment_reports;
CREATE POLICY reports_read_owner_clinician_admin ON public.equipment_reports
  FOR SELECT TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    OR public.is_current_admin()
    OR public.is_assigned_clinician(owner_uid)
  );

DROP POLICY IF EXISTS reports_create_owner_patient ON public.equipment_reports;
CREATE POLICY reports_create_owner_patient ON public.equipment_reports
  FOR INSERT TO authenticated
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );

DROP POLICY IF EXISTS reports_update_owner_or_admin ON public.equipment_reports;
CREATE POLICY reports_update_owner_or_admin ON public.equipment_reports
  FOR UPDATE TO authenticated
  USING (owner_uid = (SELECT auth.uid()) OR public.is_current_admin())
  WITH CHECK (owner_uid = (SELECT auth.uid()) OR public.is_current_admin());

DROP POLICY IF EXISTS reports_delete_owner_or_admin ON public.equipment_reports;
CREATE POLICY reports_delete_owner_or_admin ON public.equipment_reports
  FOR DELETE TO authenticated
  USING (owner_uid = (SELECT auth.uid()) OR public.is_current_admin());

DROP POLICY IF EXISTS measurements_read_owner_clinician_admin ON public.measurements;
CREATE POLICY measurements_read_owner_clinician_admin ON public.measurements
  FOR SELECT TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    OR public.is_current_admin()
    OR public.is_assigned_clinician(owner_uid)
  );

DROP POLICY IF EXISTS measurements_create_owner_patient ON public.measurements;
CREATE POLICY measurements_create_owner_patient ON public.measurements
  FOR INSERT TO authenticated
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );

DROP POLICY IF EXISTS medication_reminders_read_owner_or_clinician ON public.medication_reminders;
CREATE POLICY medication_reminders_read_owner_or_clinician ON public.medication_reminders
  FOR SELECT TO authenticated
  USING (owner_uid = (SELECT auth.uid()) OR public.is_assigned_clinician(owner_uid));

DROP POLICY IF EXISTS medication_reminders_manage_owner ON public.medication_reminders;
CREATE POLICY medication_reminders_manage_owner ON public.medication_reminders
  FOR ALL TO authenticated
  USING (owner_uid = (SELECT auth.uid()))
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );

DROP POLICY IF EXISTS measurement_settings_manage_owner ON public.measurement_reminder_settings;
CREATE POLICY measurement_settings_manage_owner ON public.measurement_reminder_settings
  FOR ALL TO authenticated
  USING (owner_uid = (SELECT auth.uid()))
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );

REVOKE ALL ON FUNCTION public.is_current_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_assigned_clinician(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_current_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_assigned_clinician(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.replace_doctor_assignments(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_doctor_assignments(uuid, uuid[]) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'equipment_reports'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.equipment_reports;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'measurements'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.measurements;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'medication_reminders'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.medication_reminders;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'measurement_reminder_settings'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.measurement_reminder_settings;
    END IF;
  END IF;
END;
$$;
