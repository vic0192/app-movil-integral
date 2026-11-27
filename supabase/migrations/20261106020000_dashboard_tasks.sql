CREATE TABLE public.dashboard_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_uid uuid NOT NULL DEFAULT auth.uid()
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 160),
  description text NOT NULL DEFAULT ''
    CHECK (length(trim(description)) <= 2000),
  priority text NOT NULL DEFAULT 'media'
    CHECK (priority IN ('alta', 'media', 'baja')),
  status text NOT NULL DEFAULT 'pendiente'
    CHECK (status IN ('pendiente', 'en_progreso', 'completada', 'cancelada')),
  due_date date,
  category text NOT NULL DEFAULT 'Operación Clínica'
    CHECK (length(trim(category)) BETWEEN 1 AND 120),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX dashboard_tasks_owner_due_idx
  ON public.dashboard_tasks(owner_uid, due_date, created_at DESC);

ALTER TABLE public.dashboard_tasks ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, DELETE ON public.dashboard_tasks TO authenticated;
GRANT UPDATE (title, description, priority, status, due_date, category)
  ON public.dashboard_tasks TO authenticated;

CREATE POLICY dashboard_tasks_select_owner ON public.dashboard_tasks
  FOR SELECT TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    AND public.is_current_user_active()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND p.role IN ('doctor', 'admin')
    )
  );

CREATE POLICY dashboard_tasks_insert_owner ON public.dashboard_tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND public.is_current_user_active()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND p.role IN ('doctor', 'admin')
    )
  );

CREATE POLICY dashboard_tasks_update_owner ON public.dashboard_tasks
  FOR UPDATE TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    AND public.is_current_user_active()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND p.role IN ('doctor', 'admin')
    )
  )
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND public.is_current_user_active()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND p.role IN ('doctor', 'admin')
    )
  );

CREATE POLICY dashboard_tasks_delete_owner ON public.dashboard_tasks
  FOR DELETE TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    AND public.is_current_user_active()
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND p.role IN ('doctor', 'admin')
    )
  );

CREATE POLICY dashboard_tasks_active_account_required ON public.dashboard_tasks
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (public.is_current_user_active())
  WITH CHECK (public.is_current_user_active());

CREATE TRIGGER dashboard_tasks_set_updated_at
  BEFORE UPDATE ON public.dashboard_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
