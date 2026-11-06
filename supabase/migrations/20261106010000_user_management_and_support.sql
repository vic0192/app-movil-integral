ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.is_current_user_active()
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
      AND p.is_active
  );
$$;

CREATE OR REPLACE FUNCTION public.set_user_active(
  target_user_uid uuid,
  target_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede actualizar el estado de una cuenta.'
      USING ERRCODE = '42501';
  END IF;

  IF target_user_uid = (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'No puedes dar de baja tu propia cuenta.'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = target_user_uid
      AND p.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'No se puede dar de baja otra cuenta administradora desde este módulo.'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
  SET is_active = target_is_active,
      updated_at = now()
  WHERE id = target_user_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró la cuenta solicitada.'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.is_current_user_active() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_current_user_active() TO authenticated;
REVOKE ALL ON FUNCTION public.set_user_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_user_active(uuid, boolean) TO authenticated;

DO $$
DECLARE
  target_table text;
  guarded_tables text[] := ARRAY[
    'profiles',
    'doctor_patient_assignments',
    'equipment_reports',
    'measurements',
    'medication_reminders',
    'measurement_reminder_settings',
    'terms_acceptances',
    'doctor_credentials',
    'clinical_conversations',
    'clinical_messages',
    'clinic_turns'
  ];
BEGIN
  FOREACH target_table IN ARRAY guarded_tables LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS active_account_access_required ON public.%I',
      target_table
    );
    IF target_table = 'profiles' THEN
      EXECUTE format(
        'CREATE POLICY active_account_access_required ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (id = (SELECT auth.uid()) OR public.is_current_user_active()) WITH CHECK (id = (SELECT auth.uid()) OR public.is_current_user_active())',
        target_table
      );
    ELSE
      EXECUTE format(
        'CREATE POLICY active_account_access_required ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.is_current_user_active()) WITH CHECK (public.is_current_user_active())',
        target_table
      );
    END IF;
  END LOOP;
END;
$$;

DROP POLICY IF EXISTS active_account_storage_access_required ON storage.objects;
CREATE POLICY active_account_storage_access_required ON storage.objects
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (public.is_current_user_active())
  WITH CHECK (public.is_current_user_active());

CREATE TABLE public.support_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  subject text NOT NULL DEFAULT 'Soporte general'
    CHECK (length(trim(subject)) BETWEEN 1 AND 160),
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX support_conversations_customer_updated_idx
  ON public.support_conversations(customer_uid, updated_at DESC);
CREATE INDEX support_conversations_status_updated_idx
  ON public.support_conversations(status, updated_at DESC);

CREATE TABLE public.support_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL
    REFERENCES public.support_conversations(id) ON DELETE CASCADE,
  sender_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 4000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX support_messages_conversation_created_idx
  ON public.support_messages(conversation_id, created_at, id);

CREATE OR REPLACE FUNCTION public.touch_support_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.support_conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER support_messages_touch_conversation
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_support_conversation();

ALTER TABLE public.support_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.support_conversations TO authenticated;
GRANT UPDATE (status) ON public.support_conversations TO authenticated;
GRANT SELECT, INSERT ON public.support_messages TO authenticated;

CREATE POLICY support_conversations_read_customer_or_admin ON public.support_conversations
  FOR SELECT TO authenticated
  USING (customer_uid = (SELECT auth.uid()) OR public.is_current_admin());

CREATE POLICY support_conversations_create_customer ON public.support_conversations
  FOR INSERT TO authenticated
  WITH CHECK (
    customer_uid = (SELECT auth.uid())
    AND NOT public.is_current_admin()
    AND status = 'open'
  );

CREATE POLICY support_conversations_update_admin ON public.support_conversations
  FOR UPDATE TO authenticated
  USING (public.is_current_admin())
  WITH CHECK (public.is_current_admin());

CREATE POLICY support_messages_read_participant_or_admin ON public.support_messages
  FOR SELECT TO authenticated
  USING (
    public.is_current_admin()
    OR EXISTS (
      SELECT 1
      FROM public.support_conversations c
      WHERE c.id = conversation_id
        AND c.customer_uid = (SELECT auth.uid())
    )
  );

CREATE POLICY support_messages_send_as_participant ON public.support_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.support_conversations c
      WHERE c.id = conversation_id
        AND (
          public.is_current_admin()
          OR (
            c.customer_uid = (SELECT auth.uid())
            AND c.status = 'open'
          )
        )
    )
  );

DROP POLICY IF EXISTS active_account_access_required ON public.support_conversations;
CREATE POLICY active_account_access_required ON public.support_conversations
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (public.is_current_user_active())
  WITH CHECK (public.is_current_user_active());

DROP POLICY IF EXISTS active_account_access_required ON public.support_messages;
CREATE POLICY active_account_access_required ON public.support_messages
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (public.is_current_user_active())
  WITH CHECK (public.is_current_user_active());

REVOKE ALL ON FUNCTION public.touch_support_conversation() FROM PUBLIC, anon;
