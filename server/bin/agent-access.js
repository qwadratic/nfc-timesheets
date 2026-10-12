#!/usr/bin/env node
// Local maintenance only. Creation prints the secret ONCE: keep terminal output private.
import { parseArgs } from "node:util";
import { createAgentAccess, listAgentAccess, revokeAgentAccess } from "../agent/auth.js";
import { pool } from "../lib/db.js";

const help = `Company agent access (DATABASE_URL required; never pass a token as an argument):
  node server/bin/agent-access.js create --tenant 1 --admin 1 --name assistant [--write] [--days 30]
  node server/bin/agent-access.js list --tenant 1
  node server/bin/agent-access.js revoke --tenant 1 --id TOKEN_ID
Read-only by default. --write adds company business mutations. Expiry: 1–365 days.
Creation prints the bearer token once. Store it in your agent's secret configuration.
Revocation does not affect the administrator's browser sessions.`;

try {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: {
    tenant: { type: "string" }, admin: { type: "string" }, name: { type: "string" },
    id: { type: "string" }, days: { type: "string" }, write: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  } });
  if (values.help) {
    console.log(help);
  } else {
    const [command] = positionals;
    const allowed = { create: ["tenant", "admin", "name", "days", "write"], list: ["tenant"], revoke: ["tenant", "id"] };
    if (positionals.length !== 1 || !allowed[command] || Object.keys(values).some((key) => !allowed[command].includes(key))) {
      throw new Error("Invalid command/options. Use --help.");
    }
    if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is not set");
    const tenantId = Number(values.tenant);
    let result;
    if (command === "create") result = await createAgentAccess({ tenantId,
      adminId: Number(values.admin), name: values.name, write: values.write ?? false,
      days: values.days === undefined ? 30 : Number(values.days) });
    if (command === "list") result = await listAgentAccess(tenantId);
    if (command === "revoke") result = await revokeAgentAccess(tenantId, values.id);
    console.log(JSON.stringify(result, null, 2));
  }
} catch (error) {
  // PostgreSQL error details can contain sensitive row values. Print only known app codes.
  console.error(`agent-access: ${error?.name === "HttpError" ? error.code : "Command failed; check options (--help) and database access."}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
