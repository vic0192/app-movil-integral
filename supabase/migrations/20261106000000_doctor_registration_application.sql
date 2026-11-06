CREATE OR REPLACE FUNCTION public.create_doctor_registration_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  registration jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  professional_license text := NULLIF(trim(registration ->> 'professional_license'), '');
  specialty text := NULLIF(trim(registration ->> 'specialty'), '');
  specialty_license text := NULLIF(trim(registration ->> 'specialty_license'), '');
  institution text := NULLIF(trim(registration ->> 'institution'), '');
  contact_phone text := NULLIF(trim(registration ->> 'contact_phone'), '');
BEGIN
  IF registration ->> 'registration_role' IS DISTINCT FROM 'doctor' THEN
    RETURN NEW;
  END IF;

  IF professional_license IS NULL
     OR length(professional_license) NOT BETWEEN 5 AND 40 THEN
    RAISE EXCEPTION 'A valid professional license is required for a doctor application.';
  END IF;
  IF specialty IS NULL OR length(specialty) > 120 THEN
    RAISE EXCEPTION 'A valid medical specialty is required for a doctor application.';
  END IF;
  IF specialty_license IS NOT NULL
     AND length(specialty_license) NOT BETWEEN 5 AND 40 THEN
    RAISE EXCEPTION 'The specialty license length is invalid.';
  END IF;
  IF institution IS NOT NULL AND length(institution) > 160 THEN
    RAISE EXCEPTION 'The institution name is too long.';
  END IF;
  IF contact_phone IS NOT NULL
     AND length(contact_phone) NOT BETWEEN 7 AND 25 THEN
    RAISE EXCEPTION 'The contact phone length is invalid.';
  END IF;

  INSERT INTO public.doctor_credentials (
    doctor_uid,
    professional_license,
    specialty,
    specialty_license,
    institution,
    contact_phone,
    verification_status
  )
  VALUES (
    NEW.id,
    professional_license,
    specialty,
    specialty_license,
    institution,
    contact_phone,
    'pending'
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.create_doctor_registration_application() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_doctor_registration ON auth.users;
CREATE TRIGGER on_auth_user_doctor_registration
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_doctor_registration_application();
