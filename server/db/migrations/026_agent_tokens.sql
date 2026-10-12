-- Dedicated integrations never reuse or rotate browser login sessions.
CREATE TABLE agent_tokens (
  id UUID PRIMARY KEY,
  tenant_id BIGINT NOT NULL DEFAULT workspace_id() REFERENCES tenants(id) CHECK (tenant_id > 0),
  admin_id BIGINT NOT NULL,
  name TEXT NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
  token_hash TEXT NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  scopes TEXT[] NOT NULL DEFAULT ARRAY['read']::text[]
    CHECK (scopes = ARRAY['read']::text[] OR scopes = ARRAY['read','write']::text[]),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (id, tenant_id),
  FOREIGN KEY (admin_id, tenant_id) REFERENCES admins(id, tenant_id),
  CHECK (expires_at > created_at)
);
CREATE INDEX agent_tokens_tenant_idx ON agent_tokens(tenant_id);
ALTER TABLE agent_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_tokens FORCE ROW LEVEL SECURITY;
CREATE POLICY workspace_scope ON agent_tokens
  USING (workspace_system() OR tenant_id = workspace_id())
  WITH CHECK (workspace_system() OR tenant_id = workspace_id());
