-- Opt-in company policy. Existing and already-running shifts stay disabled.
CREATE TABLE shift_policies (
  tenant_id BIGINT PRIMARY KEY DEFAULT workspace_id() REFERENCES tenants(id),
  location_interval_seconds INTEGER NOT NULL DEFAULT 0 CHECK (location_interval_seconds = 0 OR location_interval_seconds BETWEEN 60 AND 86400),
  proof_of_work_required BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE shifts ADD COLUMN location_interval_seconds INTEGER NOT NULL DEFAULT 0 CHECK (location_interval_seconds = 0 OR location_interval_seconds BETWEEN 60 AND 86400);
ALTER TABLE shifts ADD COLUMN proof_of_work_required BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE shifts ADD COLUMN proof_id UUID;
ALTER TABLE shifts ADD COLUMN proof_challenge_id UUID;
ALTER TABLE shifts ADD COLUMN proof_challenged_at TIMESTAMPTZ;
CREATE UNIQUE INDEX shifts_evidence_tenant_ref ON shifts(id,tenant_id);

CREATE TABLE shift_locations (
  sample_uuid UUID PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT workspace_id() REFERENCES tenants(id),
  shift_id BIGINT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  accuracy_m DOUBLE PRECISION NOT NULL CHECK (accuracy_m BETWEEN 0 AND 10000),
  FOREIGN KEY (shift_id,tenant_id) REFERENCES shifts(id,tenant_id) ON DELETE CASCADE
);
CREATE INDEX shift_locations_order ON shift_locations(tenant_id,shift_id,captured_at);
-- One bounded photo per shift; a retake replaces only the unconsumed photo.
CREATE TABLE shift_proofs (
  id UUID PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT workspace_id() REFERENCES tenants(id),
  shift_id BIGINT NOT NULL UNIQUE,
  challenge_id UUID NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  jpeg BYTEA NOT NULL CHECK (octet_length(jpeg) BETWEEN 128 AND 2097152),
  FOREIGN KEY (shift_id,tenant_id) REFERENCES shifts(id,tenant_id) ON DELETE CASCADE
);
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['shift_policies','shift_locations','shift_proofs'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tbl);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tbl);
    EXECUTE format('CREATE POLICY workspace_scope ON %I USING (workspace_system() OR tenant_id=workspace_id()) WITH CHECK (workspace_system() OR tenant_id=workspace_id())',tbl);
  END LOOP;
END $$;
