-- Durable retry keys are per connection. Response secrets are encrypted with a key
-- derived from the caller's bearer token; a database dump cannot replay them.
CREATE TABLE agent_tool_calls (
  tenant_id BIGINT NOT NULL DEFAULT workspace_id() REFERENCES tenants(id),
  token_id UUID NOT NULL,
  request_id UUID NOT NULL,
  tool_name TEXT NOT NULL,
  arguments_hash TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','completed','failed')),
  response_cipher TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (token_id,request_id),
  FOREIGN KEY (token_id,tenant_id) REFERENCES agent_tokens(id,tenant_id),
  CHECK ((state='pending') = (response_cipher IS NULL))
);
ALTER TABLE agent_tool_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_tool_calls FORCE ROW LEVEL SECURITY;
CREATE POLICY workspace_scope ON agent_tool_calls
  USING (workspace_system() OR tenant_id=workspace_id())
  WITH CHECK (workspace_system() OR tenant_id=workspace_id());
-- Existing audit readers remain platform-only. Agent writes append in the same
-- transaction as the business change without escalating to a system DB scope.
CREATE POLICY agent_audit_append ON action_log FOR INSERT WITH CHECK (
  tenant_id=workspace_id() AND actor_type='agent' AND origin='tenant'
  AND target_table='agent_tool_calls'
);
