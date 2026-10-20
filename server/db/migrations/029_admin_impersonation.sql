-- decision-85: a platform administrator can enter a company AS one of its admins.
--
-- The session belongs to the company admin (so tenant_id, RLS and every composite
-- admin reference stay exactly as they are for that admin) and additionally names the
-- superadmin who opened it. NULL means an ordinary sign-in. A plain FK, not a composite
-- one: the impersonator lives in tenant 0 by construction (admins_workspace_role).
-- Deleting the platform account revokes every company session it opened.
ALTER TABLE sessions
  ADD COLUMN impersonator_admin_id BIGINT REFERENCES admins(id) ON DELETE CASCADE;

CREATE INDEX sessions_impersonator_idx ON sessions (impersonator_admin_id)
  WHERE impersonator_admin_id IS NOT NULL;
