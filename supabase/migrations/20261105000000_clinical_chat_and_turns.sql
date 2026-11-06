CREATE TABLE public.doctor_credentials (
  doctor_uid uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  professional_license text NOT NULL
    CHECK (length(trim(professional_license)) BETWEEN 5 AND 40),
  specialty text
    CHECK (specialty IS NULL OR length(trim(specialty)) BETWEEN 1 AND 120),
  specialty_license text
    CHECK (specialty_license IS NULL OR length(trim(specialty_license)) BETWEEN 5 AND 40),
  institution text
    CHECK (institution IS NULL OR length(trim(institution)) BETWEEN 1 AND 160),
  contact_phone text
    CHECK (contact_phone IS NULL OR length(trim(contact_phone)) BETWEEN 7 AND 25),
  verification_status text NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'verified', 'rejected')),
  verification_notes text
    CHECK (verification_notes IS NULL OR length(trim(verification_notes)) <= 500),
  verified_at timestamptz,
  verified_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (verification_status = 'verified' AND verified_at IS NOT NULL AND verified_by IS NOT NULL)
    OR verification_status <> 'verified'
  )
);

CREATE TABLE public.clinical_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  patient_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (doctor_uid, patient_uid),
  CHECK (doctor_uid <> patient_uid)
);

CREATE INDEX clinical_conversations_patient_updated_idx
  ON public.clinical_conversations(patient_uid, updated_at DESC);
CREATE INDEX clinical_conversations_doctor_updated_idx
  ON public.clinical_conversations(doctor_uid, updated_at DESC);

CREATE TABLE public.clinical_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.clinical_conversations(id) ON DELETE CASCADE,
  sender_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  message_type text NOT NULL DEFAULT 'chat'
    CHECK (message_type IN ('chat', 'clinical_note', 'prescription_info')),
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 4000),
  attachment_path text
    CHECK (attachment_path IS NULL OR length(attachment_path) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

CREATE INDEX clinical_messages_conversation_created_idx
  ON public.clinical_messages(conversation_id, created_at, id);

CREATE TABLE public.clinic_turns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_code text NOT NULL UNIQUE
    CHECK (length(trim(ticket_code)) BETWEEN 2 AND 24),
  patient_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  service text NOT NULL CHECK (length(trim(service)) BETWEEN 1 AND 100),
  room text NOT NULL CHECK (length(trim(room)) BETWEEN 1 AND 100),
  priority text NOT NULL DEFAULT 'media'
    CHECK (priority IN ('alta', 'media', 'baja')),
  status text NOT NULL DEFAULT 'en_espera'
    CHECK (status IN ('en_espera', 'en_atencion', 'finalizado', 'cancelado')),
  eta_minutes smallint NOT NULL DEFAULT 0 CHECK (eta_minutes BETWEEN 0 AND 1440),
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX clinic_turns_status_created_idx
  ON public.clinic_turns(status, created_at);
CREATE INDEX clinic_turns_patient_created_idx
  ON public.clinic_turns(patient_uid, created_at DESC);

CREATE OR REPLACE FUNCTION public.is_doctor_assigned_to(
  target_doctor_uid uuid,
  target_patient_uid uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.doctor_patient_assignments a
    JOIN public.profiles d ON d.id = a.doctor_uid AND d.role = 'doctor'
    JOIN public.profiles p ON p.id = a.patient_uid AND p.role = 'patient'
    JOIN public.doctor_credentials c
      ON c.doctor_uid = a.doctor_uid AND c.verification_status = 'verified'
    WHERE a.doctor_uid = target_doctor_uid
      AND a.patient_uid = target_patient_uid
  );
$$;

CREATE OR REPLACE FUNCTION public.can_access_clinical_conversation(target_conversation_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clinical_conversations c
    WHERE c.id = target_conversation_uid
      AND (
        (c.patient_uid = (SELECT auth.uid())
          AND public.is_doctor_assigned_to(c.doctor_uid, c.patient_uid))
        OR
        (c.doctor_uid = (SELECT auth.uid())
          AND public.is_doctor_assigned_to(c.doctor_uid, c.patient_uid))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.guard_clinical_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  conversation public.clinical_conversations%ROWTYPE;
BEGIN
  SELECT * INTO conversation
  FROM public.clinical_conversations
  WHERE id = NEW.conversation_id;

  IF NOT FOUND OR NOT public.is_doctor_assigned_to(
    conversation.doctor_uid,
    conversation.patient_uid
  ) THEN
    RAISE EXCEPTION 'La conversación no está habilitada para esta relación clínica.';
  END IF;

  IF NEW.sender_uid NOT IN (conversation.doctor_uid, conversation.patient_uid) THEN
    RAISE EXCEPTION 'El autor no pertenece a esta conversación.';
  END IF;

  IF NEW.sender_uid = conversation.patient_uid AND NEW.message_type <> 'chat' THEN
    RAISE EXCEPTION 'El paciente solo puede enviar mensajes de chat.';
  END IF;

  IF NEW.attachment_path IS NOT NULL AND (
       NEW.attachment_path NOT LIKE
         conversation.id::text || '/' || NEW.sender_uid::text || '/%'
       OR NEW.attachment_path !~* '\.(jpe?g|png)$'
     ) THEN
    RAISE EXCEPTION 'El adjunto debe pertenecer al autor y a esta conversación.';
  END IF;

  IF NEW.sender_uid = conversation.doctor_uid
     AND NOT EXISTS (
       SELECT 1 FROM public.doctor_credentials
       WHERE doctor_uid = conversation.doctor_uid
         AND verification_status = 'verified'
     ) THEN
    RAISE EXCEPTION 'El médico no está verificado.';
  END IF;

  UPDATE public.clinical_conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_unverified_doctor_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.role = 'doctor' AND OLD.role IS DISTINCT FROM NEW.role
     AND NOT EXISTS (
       SELECT 1 FROM public.doctor_credentials c
       WHERE c.doctor_uid = NEW.id
         AND c.verification_status = 'verified'
     ) THEN
    RAISE EXCEPTION 'El médico debe contar con credenciales verificadas por un administrador.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_doctor_credentials_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  IF NEW.verification_status = 'verified'
     AND OLD.verification_status IS DISTINCT FROM NEW.verification_status THEN
    NEW.verified_at = now();
    NEW.verified_by = (SELECT auth.uid());
  ELSIF NEW.verification_status <> 'verified' THEN
    NEW.verified_at = NULL;
    NEW.verified_by = NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_clinical_conversation(target_doctor_uid uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_uid uuid := (SELECT auth.uid());
  conversation_uid uuid;
BEGIN
  IF current_uid IS NULL
     OR NOT public.is_doctor_assigned_to(target_doctor_uid, current_uid) THEN
    RAISE EXCEPTION 'Solo puedes iniciar una conversación con un médico asignado.';
  END IF;

  INSERT INTO public.clinical_conversations (doctor_uid, patient_uid)
  VALUES (target_doctor_uid, current_uid)
  ON CONFLICT (doctor_uid, patient_uid)
  DO UPDATE SET updated_at = public.clinical_conversations.updated_at
  RETURNING id INTO conversation_uid;
  RETURN conversation_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.public_clinic_turn_feed()
RETURNS TABLE (
  ticket_code text,
  service text,
  room text,
  status text,
  eta_minutes smallint,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT t.ticket_code, t.service, t.room, t.status, t.eta_minutes, t.updated_at
  FROM public.clinic_turns t
  WHERE t.status IN ('en_espera', 'en_atencion')
  ORDER BY (t.status = 'en_atencion') DESC, t.created_at
  LIMIT 20;
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
    SELECT 1
    FROM public.profiles p
    JOIN public.doctor_credentials c ON c.doctor_uid = p.id
    WHERE p.id = target_doctor_uid
      AND p.role = 'doctor'
      AND c.verification_status = 'verified'
  ) THEN
    RAISE EXCEPTION 'The selected clinician is not a verified doctor.';
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

DROP TRIGGER IF EXISTS clinical_messages_guard ON public.clinical_messages;
CREATE TRIGGER clinical_messages_guard
  BEFORE INSERT ON public.clinical_messages
  FOR EACH ROW EXECUTE FUNCTION public.guard_clinical_message();

DROP TRIGGER IF EXISTS clinical_conversations_set_updated_at ON public.clinical_conversations;
CREATE TRIGGER clinical_conversations_set_updated_at
  BEFORE UPDATE ON public.clinical_conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS doctor_credentials_set_updated_at ON public.doctor_credentials;
CREATE TRIGGER doctor_credentials_set_updated_at
  BEFORE UPDATE ON public.doctor_credentials
  FOR EACH ROW EXECUTE FUNCTION public.set_doctor_credentials_updated_at();

DROP TRIGGER IF EXISTS profiles_prevent_unverified_doctor_role ON public.profiles;
CREATE TRIGGER profiles_prevent_unverified_doctor_role
  BEFORE UPDATE OF role ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_unverified_doctor_role();

ALTER TABLE public.doctor_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinic_turns ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.doctor_credentials TO authenticated;
GRANT SELECT, INSERT ON public.clinical_conversations TO authenticated;
GRANT SELECT, INSERT ON public.clinical_messages TO authenticated;
GRANT UPDATE (read_at) ON public.clinical_messages TO authenticated;
GRANT SELECT, INSERT ON public.clinic_turns TO authenticated;
REVOKE UPDATE ON public.clinic_turns FROM authenticated;
GRANT UPDATE (
  ticket_code,
  patient_uid,
  service,
  room,
  priority,
  status,
  eta_minutes
) ON public.clinic_turns TO authenticated;

DROP POLICY IF EXISTS profiles_read_assigned_doctor_by_patient ON public.profiles;
CREATE POLICY profiles_read_assigned_doctor_by_patient ON public.profiles
  FOR SELECT TO authenticated
  USING (
    role = 'doctor'
    AND EXISTS (
      SELECT 1 FROM public.doctor_patient_assignments a
      WHERE a.doctor_uid = id
        AND a.patient_uid = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS assignments_manage_admin ON public.doctor_patient_assignments;
CREATE POLICY assignments_manage_admin ON public.doctor_patient_assignments
  FOR ALL TO authenticated
  USING (public.is_current_admin())
  WITH CHECK (
    public.is_current_admin()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      JOIN public.doctor_credentials c ON c.doctor_uid = p.id
      WHERE p.id = doctor_uid
        AND p.role = 'doctor'
        AND c.verification_status = 'verified'
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = patient_uid AND p.role = 'patient'
    )
  );

DROP POLICY IF EXISTS doctor_credentials_read_related ON public.doctor_credentials;
CREATE POLICY doctor_credentials_read_related ON public.doctor_credentials
  FOR SELECT TO authenticated
  USING (
    doctor_uid = (SELECT auth.uid())
    OR public.is_current_admin()
    OR (
      verification_status = 'verified'
      AND EXISTS (
        SELECT 1 FROM public.doctor_patient_assignments a
        WHERE a.doctor_uid = doctor_uid
          AND a.patient_uid = (SELECT auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS doctor_credentials_submit_self ON public.doctor_credentials;
CREATE POLICY doctor_credentials_submit_self ON public.doctor_credentials
  FOR INSERT TO authenticated
  WITH CHECK (
    doctor_uid = (SELECT auth.uid())
    AND verification_status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );

DROP POLICY IF EXISTS doctor_credentials_update_pending_self ON public.doctor_credentials;
CREATE POLICY doctor_credentials_update_pending_self ON public.doctor_credentials
  FOR UPDATE TO authenticated
  USING (
    doctor_uid = (SELECT auth.uid())
    AND verification_status = 'pending'
  )
  WITH CHECK (
    doctor_uid = (SELECT auth.uid())
    AND verification_status = 'pending'
  );

DROP POLICY IF EXISTS doctor_credentials_admin_manage ON public.doctor_credentials;
CREATE POLICY doctor_credentials_admin_manage ON public.doctor_credentials
  FOR ALL TO authenticated
  USING (public.is_current_admin())
  WITH CHECK (public.is_current_admin());

DROP POLICY IF EXISTS clinical_conversations_read_participants ON public.clinical_conversations;
CREATE POLICY clinical_conversations_read_participants ON public.clinical_conversations
  FOR SELECT TO authenticated
  USING (
    (patient_uid = (SELECT auth.uid()) OR doctor_uid = (SELECT auth.uid()))
    AND public.is_doctor_assigned_to(doctor_uid, patient_uid)
  );

DROP POLICY IF EXISTS clinical_conversations_start_assigned_patient ON public.clinical_conversations;
CREATE POLICY clinical_conversations_start_assigned_patient ON public.clinical_conversations
  FOR INSERT TO authenticated
  WITH CHECK (
    (
      patient_uid = (SELECT auth.uid())
      OR doctor_uid = (SELECT auth.uid())
    )
    AND public.is_doctor_assigned_to(doctor_uid, patient_uid)
  );

DROP POLICY IF EXISTS clinical_messages_read_participants ON public.clinical_messages;
CREATE POLICY clinical_messages_read_participants ON public.clinical_messages
  FOR SELECT TO authenticated
  USING (public.can_access_clinical_conversation(conversation_id));

DROP POLICY IF EXISTS clinical_messages_send_as_self ON public.clinical_messages;
CREATE POLICY clinical_messages_send_as_self ON public.clinical_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_uid = (SELECT auth.uid())
    AND public.can_access_clinical_conversation(conversation_id)
  );

DROP POLICY IF EXISTS clinical_messages_recipient_mark_read ON public.clinical_messages;
CREATE POLICY clinical_messages_recipient_mark_read ON public.clinical_messages
  FOR UPDATE TO authenticated
  USING (
    sender_uid <> (SELECT auth.uid())
    AND public.can_access_clinical_conversation(conversation_id)
  )
  WITH CHECK (
    sender_uid <> (SELECT auth.uid())
    AND public.can_access_clinical_conversation(conversation_id)
  );

DROP POLICY IF EXISTS clinic_turns_admin_manage ON public.clinic_turns;
DROP POLICY IF EXISTS clinic_turns_admin_insert ON public.clinic_turns;
DROP POLICY IF EXISTS clinic_turns_admin_update ON public.clinic_turns;
CREATE POLICY clinic_turns_admin_insert ON public.clinic_turns
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_current_admin()
    AND created_by = (SELECT auth.uid())
  );

CREATE POLICY clinic_turns_admin_update ON public.clinic_turns
  FOR UPDATE TO authenticated
  USING (public.is_current_admin())
  WITH CHECK (public.is_current_admin());

DROP POLICY IF EXISTS clinic_turns_read_own_or_care_team ON public.clinic_turns;
CREATE POLICY clinic_turns_read_own_or_care_team ON public.clinic_turns
  FOR SELECT TO authenticated
  USING (
    public.is_current_admin()
    OR patient_uid = (SELECT auth.uid())
    OR public.is_assigned_clinician(patient_uid)
  );

REVOKE ALL ON FUNCTION public.is_doctor_assigned_to(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_clinical_conversation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_clinical_message() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prevent_unverified_doctor_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_clinical_conversation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.public_clinic_turn_feed() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_doctor_assigned_to(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_clinical_conversation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_clinical_conversation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.public_clinic_turn_feed() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.replace_doctor_assignments(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_doctor_assignments(uuid, uuid[]) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'clinical_messages'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.clinical_messages;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'clinical_conversations'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.clinical_conversations;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'clinic_turns'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.clinic_turns;
    END IF;
  END IF;
END;
$$;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'clinical-attachments',
  'clinical-attachments',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png']::text[];

DROP POLICY IF EXISTS clinical_attachments_read_participants ON storage.objects;
CREATE POLICY clinical_attachments_read_participants ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'clinical-attachments'
    AND public.can_access_clinical_conversation(
      ((storage.foldername(name))[1])::uuid
    )
  );

DROP POLICY IF EXISTS clinical_attachments_upload_own ON storage.objects;
CREATE POLICY clinical_attachments_upload_own ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'clinical-attachments'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND public.can_access_clinical_conversation(
      ((storage.foldername(name))[1])::uuid
    )
  );

DROP POLICY IF EXISTS clinical_attachments_delete_own ON storage.objects;
CREATE POLICY clinical_attachments_delete_own ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'clinical-attachments'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND public.can_access_clinical_conversation(
      ((storage.foldername(name))[1])::uuid
    )
  );
