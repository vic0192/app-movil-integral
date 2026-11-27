ALTER TABLE public.measurements
  ADD COLUMN IF NOT EXISTS sensor_readings jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.measurements'::regclass
      AND conname = 'measurements_sensor_readings_object'
  ) THEN
    ALTER TABLE public.measurements
      ADD CONSTRAINT measurements_sensor_readings_object
      CHECK (jsonb_typeof(sensor_readings) = 'object');
  END IF;
END;
$$;
