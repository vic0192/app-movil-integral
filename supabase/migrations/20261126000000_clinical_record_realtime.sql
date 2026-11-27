ALTER TABLE public.health_connect_records
  DROP CONSTRAINT IF EXISTS health_connect_records_data_type_check;

ALTER TABLE public.health_connect_records
  ADD CONSTRAINT health_connect_records_data_type_check
  CHECK (data_type IN (
    'HEART_RATE',
    'RESTING_HEART_RATE',
    'BLOOD_OXYGEN',
    'BODY_TEMPERATURE',
    'BLOOD_PRESSURE_SYSTOLIC',
    'BLOOD_PRESSURE_DIASTOLIC',
    'BODY_FAT_PERCENTAGE',
    'LEAN_BODY_MASS',
    'BODY_MASS_INDEX',
    'BODY_WATER_MASS',
    'WEIGHT',
    'HEIGHT',
    'SLEEP_SESSION',
    'SLEEP_ASLEEP',
    'SLEEP_AWAKE',
    'SLEEP_AWAKE_IN_BED',
    'SLEEP_DEEP',
    'SLEEP_LIGHT',
    'SLEEP_OUT_OF_BED',
    'SLEEP_REM',
    'SLEEP_UNKNOWN'
  ));

CREATE TABLE public.clinical_record_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  author_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  entry_type text NOT NULL CHECK (
    entry_type IN ('diagnosis', 'clinical_note', 'medication', 'allergy', 'visit')
  ),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 160),
  details text NOT NULL CHECK (length(trim(details)) BETWEEN 1 AND 4000),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (patient_uid <> author_uid)
);

CREATE INDEX clinical_record_entries_patient_occurred_idx
  ON public.clinical_record_entries(patient_uid, occurred_at DESC);

ALTER TABLE public.clinical_record_entries ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.clinical_record_entries TO authenticated;

CREATE POLICY clinical_record_entries_read_patient_or_care_team
  ON public.clinical_record_entries
  FOR SELECT TO authenticated
  USING (
    patient_uid = (SELECT auth.uid())
    OR public.is_current_admin()
    OR public.is_assigned_clinician(patient_uid)
  );

CREATE POLICY clinical_record_entries_create_assigned_doctor
  ON public.clinical_record_entries
  FOR INSERT TO authenticated
  WITH CHECK (
    author_uid = (SELECT auth.uid())
    AND public.is_assigned_clinician(patient_uid)
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'doctor'
    )
  );

CREATE OR REPLACE FUNCTION public.open_clinical_conversation(
  target_patient_uid uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_uid uuid := (SELECT auth.uid());
  current_role text;
  doctor_uid uuid;
  patient_uid uuid;
  conversation_uid uuid;
BEGIN
  SELECT p.role INTO current_role
  FROM public.profiles p
  WHERE p.id = current_uid AND p.is_active;

  IF current_role = 'doctor'
     AND public.is_doctor_assigned_to(current_uid, target_patient_uid) THEN
    doctor_uid := current_uid;
    patient_uid := target_patient_uid;
  ELSIF current_role = 'patient'
     AND public.is_doctor_assigned_to(target_patient_uid, current_uid) THEN
    doctor_uid := target_patient_uid;
    patient_uid := current_uid;
  ELSE
    RAISE EXCEPTION 'Solo puedes abrir una conversación con tu médico o paciente asignado.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.clinical_conversations (doctor_uid, patient_uid)
  VALUES (doctor_uid, patient_uid)
  ON CONFLICT (doctor_uid, patient_uid)
  DO UPDATE SET updated_at = public.clinical_conversations.updated_at
  RETURNING id INTO conversation_uid;
  RETURN conversation_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.open_clinical_conversation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_clinical_conversation(uuid) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'health_connect_records'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.health_connect_records;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'clinical_record_entries'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.clinical_record_entries;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'profiles'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'doctor_patient_assignments'
    ) THEN
      ALTER PUBLICATION supabase_realtime
        ADD TABLE public.doctor_patient_assignments;
    END IF;
  END IF;
END;
$$;
