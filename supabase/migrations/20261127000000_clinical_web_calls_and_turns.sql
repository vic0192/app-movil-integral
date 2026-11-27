CREATE SEQUENCE IF NOT EXISTS public.clinic_turn_ticket_code_seq;

DO $$
DECLARE
  last_ticket_number bigint;
BEGIN
  SELECT max(substring(ticket_code FROM 3)::bigint)
  INTO last_ticket_number
  FROM public.clinic_turns
  WHERE ticket_code ~ '^T-[0-9]+$';

  IF last_ticket_number IS NULL THEN
    PERFORM setval('public.clinic_turn_ticket_code_seq', 1, false);
  ELSE
    PERFORM setval(
      'public.clinic_turn_ticket_code_seq',
      GREATEST(last_ticket_number, 1),
      true
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_clinic_turn(
  target_patient_uid uuid,
  target_service text,
  target_room text,
  target_priority text,
  target_eta_minutes integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_uid uuid := (SELECT auth.uid());
  generated_code text;
  created_turn public.clinic_turns%ROWTYPE;
  next_ticket_number bigint;
  attempt integer;
BEGIN
  IF actor_uid IS NULL OR NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Only an administrator can create clinic turns.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = target_patient_uid AND role = 'patient'
  ) THEN
    RAISE EXCEPTION 'Select a valid patient for the clinic turn.';
  END IF;

  IF target_service IS NULL OR length(trim(target_service)) NOT BETWEEN 1 AND 100
     OR target_room IS NULL OR length(trim(target_room)) NOT BETWEEN 1 AND 100
     OR target_priority IS NULL
     OR target_priority NOT IN ('alta', 'media', 'baja')
     OR target_eta_minutes IS NULL
     OR target_eta_minutes NOT BETWEEN 0 AND 1440 THEN
    RAISE EXCEPTION 'The clinic turn details are invalid.';
  END IF;

  FOR attempt IN 1..5 LOOP
    next_ticket_number := nextval('public.clinic_turn_ticket_code_seq');
    generated_code := 'T-' || lpad(
      next_ticket_number::text,
      GREATEST(6, length(next_ticket_number::text)),
      '0'
    );

    INSERT INTO public.clinic_turns (
      ticket_code,
      patient_uid,
      service,
      room,
      priority,
      eta_minutes,
      created_by
    )
    VALUES (
      generated_code,
      target_patient_uid,
      trim(target_service),
      trim(target_room),
      target_priority,
      target_eta_minutes,
      actor_uid
    )
    ON CONFLICT (ticket_code) DO NOTHING
    RETURNING * INTO created_turn;

    IF FOUND THEN
      RETURN to_jsonb(created_turn);
    END IF;
  END LOOP;

  RAISE EXCEPTION 'A unique clinic turn code could not be allocated.';
END;
$$;

CREATE OR REPLACE FUNCTION public.review_doctor_registration(
  target_doctor_uid uuid,
  target_decision text,
  target_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  doctor_role text;
BEGIN
  IF NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Only an administrator can review doctor credentials.';
  END IF;

  IF target_decision IS NULL
     OR target_decision NOT IN ('verified', 'rejected')
     OR (target_notes IS NOT NULL AND length(trim(target_notes)) > 500) THEN
    RAISE EXCEPTION 'The doctor credential decision is invalid.';
  END IF;

  SELECT role INTO doctor_role
  FROM public.profiles
  WHERE id = target_doctor_uid;

  IF doctor_role IS NULL THEN
    RAISE EXCEPTION 'The doctor account could not be found.';
  END IF;

  UPDATE public.doctor_credentials
  SET verification_status = target_decision,
      verification_notes = NULLIF(trim(target_notes), '')
  WHERE doctor_uid = target_doctor_uid
    AND verification_status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The doctor application is no longer pending.';
  END IF;

  IF target_decision = 'verified' THEN
    IF doctor_role <> 'patient' THEN
      RAISE EXCEPTION 'The applicant account is not eligible for doctor approval.';
    END IF;
    UPDATE public.profiles
    SET role = 'doctor'
    WHERE id = target_doctor_uid
      AND role = 'patient';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'The doctor account could not be updated.';
    END IF;
  END IF;
END;
$$;

CREATE TABLE public.clinical_video_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  patient_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  room_name text NOT NULL UNIQUE
    CHECK (room_name ~ '^BioMedicaDemo-[A-Za-z0-9_-]{24}$'),
  status text NOT NULL DEFAULT 'ringing'
    CHECK (status IN ('ringing', 'accepted', 'declined', 'ended', 'expired')),
  expires_at timestamptz NOT NULL,
  responded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (staff_uid <> patient_uid)
);

CREATE UNIQUE INDEX clinical_video_calls_one_active_patient_idx
  ON public.clinical_video_calls(patient_uid)
  WHERE status IN ('ringing', 'accepted');
CREATE INDEX clinical_video_calls_patient_created_idx
  ON public.clinical_video_calls(patient_uid, created_at DESC);
CREATE INDEX clinical_video_calls_staff_created_idx
  ON public.clinical_video_calls(staff_uid, created_at DESC);

CREATE OR REPLACE FUNCTION public.create_clinical_video_call(
  target_patient_uid uuid,
  target_room_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_uid uuid := (SELECT auth.uid());
  actor_role text;
  created_call public.clinical_video_calls%ROWTYPE;
BEGIN
  IF actor_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in before starting a clinical call.';
  END IF;

  SELECT role INTO actor_role
  FROM public.profiles
  WHERE id = actor_uid;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = target_patient_uid AND role = 'patient'
  ) THEN
    RAISE EXCEPTION 'Select a valid patient for the clinical call.';
  END IF;

  IF actor_role IS DISTINCT FROM 'admin'
     AND (
       actor_role IS DISTINCT FROM 'doctor'
       OR NOT public.is_doctor_assigned_to(actor_uid, target_patient_uid)
     ) THEN
    RAISE EXCEPTION 'The clinical call is not allowed for this patient.';
  END IF;

  IF target_room_name IS NULL
     OR target_room_name !~ '^BioMedicaDemo-[A-Za-z0-9_-]{24}$' THEN
    RAISE EXCEPTION 'The clinical call room is invalid.';
  END IF;

  UPDATE public.clinical_video_calls
  SET status = 'expired',
      responded_at = now()
  WHERE patient_uid = target_patient_uid
    AND status IN ('ringing', 'accepted')
    AND expires_at <= now();

  INSERT INTO public.clinical_video_calls (
    staff_uid,
    patient_uid,
    room_name,
    expires_at
  )
  VALUES (
    actor_uid,
    target_patient_uid,
    target_room_name,
    now() + interval '10 minutes'
  )
  RETURNING * INTO created_call;

  RETURN to_jsonb(created_call);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_clinical_video_call(
  target_call_uid uuid,
  target_response text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  updated_call public.clinical_video_calls%ROWTYPE;
BEGIN
  IF target_response IS NULL
     OR target_response NOT IN ('accepted', 'declined') THEN
    RAISE EXCEPTION 'The clinical call response is invalid.';
  END IF;

  UPDATE public.clinical_video_calls
  SET status = target_response,
      responded_at = now()
  WHERE id = target_call_uid
    AND patient_uid = (SELECT auth.uid())
    AND status = 'ringing'
    AND expires_at > now()
  RETURNING * INTO updated_call;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The clinical call invitation expired or is unavailable.';
  END IF;

  RETURN to_jsonb(updated_call);
END;
$$;

ALTER TABLE public.clinical_video_calls ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.clinical_video_calls TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.clinical_video_calls FROM authenticated;
REVOKE INSERT ON public.clinic_turns FROM authenticated;

DROP TRIGGER IF EXISTS clinic_turns_set_updated_at ON public.clinic_turns;
CREATE TRIGGER clinic_turns_set_updated_at
  BEFORE UPDATE ON public.clinic_turns
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP POLICY IF EXISTS clinical_video_calls_read_participants
  ON public.clinical_video_calls;
CREATE POLICY clinical_video_calls_read_participants
  ON public.clinical_video_calls
  FOR SELECT TO authenticated
  USING (
    staff_uid = (SELECT auth.uid())
    OR patient_uid = (SELECT auth.uid())
    OR public.is_current_admin()
  );

REVOKE ALL ON FUNCTION public.create_clinic_turn(
  uuid, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_clinic_turn(
  uuid, text, text, text, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.review_doctor_registration(
  uuid, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_doctor_registration(
  uuid, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.create_clinical_video_call(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_clinical_video_call(uuid, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public.respond_clinical_video_call(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_clinical_video_call(uuid, text)
  TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'clinical_video_calls'
     ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.clinical_video_calls;
  END IF;
END;
$$;
