CREATE TABLE IF NOT EXISTS app_users (
    id TEXT PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL CHECK (length(trim(display_name)) > 0),
    email VARCHAR(254) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(16) NOT NULL DEFAULT 'patient'
        CHECK (role IN ('patient', 'doctor', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS patient_assignments (
    doctor_uid TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    patient_uid TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (doctor_uid, patient_uid),
    CHECK (doctor_uid <> patient_uid)
);

CREATE INDEX IF NOT EXISTS patient_assignments_patient_idx
    ON patient_assignments(patient_uid);

CREATE TABLE IF NOT EXISTS measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    legacy_measurement_id TEXT UNIQUE,
    owner_uid TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    reading_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source VARCHAR(32) NOT NULL
        CHECK (source IN ('wear_os_sensor', 'ble_hr')),
    device_name VARCHAR(100) NOT NULL CHECK (length(trim(device_name)) > 0),
    heart_rate_bpm SMALLINT NOT NULL CHECK (heart_rate_bpm BETWEEN 30 AND 220),
    oxygen_saturation_percent SMALLINT
        CHECK (oxygen_saturation_percent BETWEEN 50 AND 100),
    body_temperature_celsius NUMERIC(4, 1)
        CHECK (body_temperature_celsius BETWEEN 25 AND 45)
);

CREATE INDEX IF NOT EXISTS measurements_owner_reading_idx
    ON measurements(owner_uid, reading_at DESC);
