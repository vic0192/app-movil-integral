CREATE TABLE IF NOT EXISTS public.terms_acceptances (
  user_uid uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  terms_version text NOT NULL CHECK (terms_version = '1.0'),
  accepted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.terms_acceptances ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.terms_acceptances FROM anon, authenticated;
GRANT SELECT ON public.terms_acceptances TO authenticated;

DROP POLICY IF EXISTS terms_acceptances_read_self
  ON public.terms_acceptances;
CREATE POLICY terms_acceptances_read_self
  ON public.terms_acceptances
  FOR SELECT
  TO authenticated
  USING (user_uid = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.record_signup_terms_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.raw_user_meta_data ->> 'terms_accepted' IS DISTINCT FROM 'true'
     OR NEW.raw_user_meta_data ->> 'terms_version' IS DISTINCT FROM '1.0' THEN
    RAISE EXCEPTION 'You must accept the current BioMedica terms to register.';
  END IF;

  INSERT INTO public.terms_acceptances (user_uid, terms_version, accepted_at)
  VALUES (NEW.id, '1.0', now())
  ON CONFLICT (user_uid) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_terms_accepted ON auth.users;
CREATE TRIGGER on_auth_user_terms_accepted
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.record_signup_terms_acceptance();