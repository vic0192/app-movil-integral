CREATE SEQUENCE IF NOT EXISTS public.clinic_turn_ticket_code_seq;

LOCK TABLE public.clinic_turns IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  last_ticket_number bigint;
BEGIN
  SELECT max(substring(ticket_code FROM 3)::bigint)
  INTO last_ticket_number
  FROM public.clinic_turns
  WHERE ticket_code ~ '^T-[0-9]{1,18}$';

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

REVOKE ALL ON FUNCTION public.create_clinic_turn(
  uuid, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_clinic_turn(
  uuid, text, text, text, integer
) TO authenticated;
