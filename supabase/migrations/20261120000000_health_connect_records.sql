CREATE TABLE public.health_connect_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_uid uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  external_id text NOT NULL,
  data_type text NOT NULL CHECK (data_type IN (
    'HEART_RATE',
    'RESTING_HEART_RATE',
    'BLOOD_OXYGEN',
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
  )),
  label text NOT NULL,
  value double precision NOT NULL,
  unit text NOT NULL,
  recorded_at timestamptz NOT NULL,
  ended_at timestamptz NOT NULL,
  source_name text NOT NULL DEFAULT '',
  source_id text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT health_connect_records_owner_external_unique
    UNIQUE (owner_uid, external_id),
  CONSTRAINT health_connect_records_valid_interval
    CHECK (ended_at >= recorded_at),
  CONSTRAINT health_connect_records_finite_value
    CHECK (value > '-Infinity'::double precision AND value < 'Infinity'::double precision)
);

CREATE INDEX health_connect_records_owner_recorded_idx
  ON public.health_connect_records(owner_uid, recorded_at DESC);

ALTER TABLE public.health_connect_records ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.health_connect_records TO authenticated;

CREATE POLICY health_connect_records_read_owner_clinician_admin
  ON public.health_connect_records
  FOR SELECT TO authenticated
  USING (
    owner_uid = (SELECT auth.uid())
    OR public.is_current_admin()
    OR public.is_assigned_clinician(owner_uid)
  );

CREATE POLICY health_connect_records_create_owner_patient
  ON public.health_connect_records
  FOR INSERT TO authenticated
  WITH CHECK (
    owner_uid = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'patient'
    )
  );
