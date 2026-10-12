// A bearer token authorizes one company, never a caller-selected workspace.
import { randomBytes, randomUUID } from "node:crypto";
import { hashToken } from "../lib/auth.js";
import { all, one, withSystem, withWorkspace } from "../lib/db.js";
import { fail } from "../lib/http.js";

const TOKEN_RE = /^nfc_agent_[0-9a-f]{64}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function authenticateAgent(headers) {
  const authorization = headers.authorization;
  if (typeof authorization !== "string") fail(401, "unauthorized");
  const match = /^Bearer (\S+)$/i.exec(authorization);
  if (!match || !TOKEN_RE.test(match[1])) fail(401, "unauthorized");
  const row = await withSystem(() => one(
    `SELECT k.id, k.admin_id, k.tenant_id, k.scopes, a.email, a.role
       FROM agent_tokens k
       JOIN admins a ON a.id = k.admin_id AND a.tenant_id = k.tenant_id
       JOIN tenants t ON t.id = k.tenant_id AND t.active
      WHERE k.token_hash = $1 AND k.revoked_at IS NULL AND k.expires_at > now()
        AND k.tenant_id > 0 AND a.role = 'admin'`,
    [hashToken(match[1])],
  ));
  if (!row) fail(401, "unauthorized");
  return { adminId: row.admin_id, tenantId: row.tenant_id, email: row.email,
    role: row.role, agentTokenId: row.id, scopes: row.scopes };
}

export function requireAgentScope(session, scope) {
  if (!["read", "write"].includes(scope) || !session?.scopes?.includes(scope)) {
    fail(403, "insufficient_scope");
  }
}

function tenantIdChecked(tenantId) {
  if (!Number.isSafeInteger(tenantId) || tenantId <= 0) fail(400, "invalid_tenant");
}

// Maintenance entry points: only the local CLI calls these. No HTTP token minting route.
export async function createAgentAccess({ tenantId, adminId, name, write = false, days = 30 }) {
  tenantIdChecked(tenantId);
  if (!Number.isSafeInteger(adminId) || adminId <= 0) fail(400, "invalid_admin");
  if (typeof name !== "string" || !name.trim() || name.trim().length > 120) fail(400, "invalid_name");
  if (typeof write !== "boolean") fail(400, "invalid_scope");
  if (!Number.isInteger(days) || days < 1 || days > 365) fail(400, "invalid_expiry_days");
  const token = `nfc_agent_${randomBytes(32).toString("hex")}`;
  const expiresAt = new Date(Date.now() + days * 86_400_000);
  const scopes = write ? ["read", "write"] : ["read"];
  // INSERT ... SELECT keeps role/tenant validation in the same statement as issuance.
  const row = await withWorkspace(tenantId, () => one(
    `INSERT INTO agent_tokens (id,tenant_id,admin_id,name,token_hash,scopes,expires_at)
     SELECT $1,a.tenant_id,a.id,$4,$5,$6,$7 FROM admins a
       JOIN tenants t ON t.id=a.tenant_id AND t.active
      WHERE a.id=$3 AND a.tenant_id=$2 AND a.role='admin' AND a.tenant_id>0
     RETURNING id,tenant_id,admin_id,name,scopes,expires_at,created_at`,
    [randomUUID(), tenantId, adminId, name.trim(), hashToken(token), scopes, expiresAt],
  ));
  if (!row) fail(400, "admin_not_eligible_for_company");
  return { ...row, token };
}

export async function listAgentAccess(tenantId) {
  tenantIdChecked(tenantId);
  return withWorkspace(tenantId, () => all(
    `SELECT id,tenant_id,admin_id,name,scopes,expires_at,revoked_at,created_at
       FROM agent_tokens WHERE tenant_id=$1 ORDER BY created_at DESC,id`, [tenantId],
  ));
}

export async function revokeAgentAccess(tenantId, id) {
  tenantIdChecked(tenantId);
  if (typeof id !== "string" || !UUID_RE.test(id)) fail(400, "invalid_token_id");
  const row = await withWorkspace(tenantId, () => one(
    `UPDATE agent_tokens SET revoked_at=coalesce(revoked_at,now())
      WHERE id=$1 AND tenant_id=$2 RETURNING id,revoked_at`, [id, tenantId],
  ));
  if (!row) fail(404, "agent_token_not_found");
  return row;
}
