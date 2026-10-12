import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { one, query, transaction, withWorkspace } from "../lib/db.js";
import { fail, HttpError, readJson, sendJson } from "../lib/http.js";
import { authenticateAgent, requireAgentScope } from "./auth.js";
import { agentTools, resolveToolCall } from "./catalog.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const writable = (tool) => !tool.annotations.readOnlyHint;

export function discoverTools(session) {
  return agentTools.filter((tool) => !writable(tool) || session.scopes.includes("write"))
    .map(({ name, description, inputSchema, annotations }) => ({
      name, description, annotations,
      inputSchema: !annotations.readOnlyHint ? {
        ...inputSchema,
        properties: { ...inputSchema.properties, request_id: {
          type: "string", format: "uuid",
          description: "Generate one UUID for this intended change; reuse it only when retrying the identical change. Never change it to bypass a pending/failed result.",
        } },
        required: [...(inputSchema.required ?? []), "request_id"],
      } : inputSchema,
    }));
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

function responseKey(authorization) {
  const token = authorization.split(" ")[1];
  return createHash("sha256").update(`agent-response-v1:${token}`).digest();
}

function encrypt(value, key) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), data]).toString("base64");
}

function decrypt(value, key) {
  const data = Buffer.from(value, "base64");
  const cipher = createDecipheriv("aes-256-gcm", key, data.subarray(0, 12));
  cipher.setAuthTag(data.subarray(12, 28));
  return JSON.parse(Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString("utf8"));
}

async function execute(name, envelope, session, headers, ip, routes) {
  if (!envelope || Object.keys(envelope).some((key) => !["arguments", "request_id"].includes(key))) {
    fail(400, "invalid_tool_envelope");
  }
  const args = envelope.arguments ?? {};
  const resolved = resolveToolCall(name, args);
  const { tool, method, path, params, query: search, body } = resolved;
  requireAgentScope(session, writable(tool) ? "write" : "read");
  const route = routes.find((entry) => entry.method === method && entry.path === path && entry.auth === "admin");
  if (!route) fail(404, "unknown_tool");
  const invoke = async () => {
    // Do not forward credentials into business handlers. Identity is verified above.
    const result = await route.handler({ params, query: search, body, session, headers: {}, ip });
    if (result.status >= 400) fail(result.status, result.body?.error ?? "tool_failed", result.body);
    return { status: result.status, result: result.body };
  };
  if (!writable(tool)) return invoke();
  const requestId = envelope.request_id;
  if (typeof requestId !== "string" || !UUID.test(requestId)) fail(400, "request_id_required");
  const hash = createHash("sha256").update(JSON.stringify(canonical(args))).digest("hex");
  const key = responseKey(headers.authorization);
  // Commit reservation before any external effect (SMS/geocoding). A crashed or
  // disconnected operation stays pending and is never silently issued twice.
  const reserved = await one(`INSERT INTO agent_tool_calls
    (token_id,request_id,tool_name,arguments_hash) VALUES ($1,$2,$3,$4)
    ON CONFLICT DO NOTHING RETURNING request_id`, [session.agentTokenId, requestId, name, hash]);
  if (!reserved) {
    const previous = await one("SELECT * FROM agent_tool_calls WHERE token_id=$1 AND request_id=$2", [session.agentTokenId, requestId]);
    if (!previous || previous.tool_name !== name || previous.arguments_hash !== hash) fail(409, "request_id_conflict");
    if (previous.state === "pending") fail(409, "operation_pending", "Do not retry with a new ID; inspect the company records before another action.");
    const cached = decrypt(previous.response_cipher, key);
    if (previous.state === "failed") fail(cached.status, cached.error, cached.detail);
    return { ...cached, request_id: requestId, replayed: true };
  }
  try {
    const result = await transaction(async () => {
      const outcome = await invoke();
      await query(`INSERT INTO action_log
        (tenant_id,actor_type,actor_id,device_id,origin,action,target_table,target_id)
        VALUES ($1,'agent',$2,$3,'tenant',$4,'agent_tool_calls',$5)`,
      [session.tenantId, session.adminId, session.agentTokenId, name, requestId]);
      await query("UPDATE agent_tool_calls SET state='completed',response_cipher=$3 WHERE token_id=$1 AND request_id=$2",
        [session.agentTokenId, requestId, encrypt(outcome, key)]);
      return outcome;
    });
    return { ...result, request_id: requestId, replayed: false };
  } catch (error) {
    // Unexpected errors/commit uncertainty remain pending: do not claim failure or
    // repeat an external side effect when its outcome is unknown.
    if (error instanceof HttpError) {
      const outcome = { status: error.status, error: error.code, detail: error.detail };
      await query("UPDATE agent_tool_calls SET state='failed',response_cipher=$3 WHERE token_id=$1 AND request_id=$2 AND state='pending'",
        [session.agentTokenId, requestId, encrypt(outcome, key)]);
    }
    throw error;
  }
}

export async function handleAgent(req, res, url, routes, ip) {
  // Machine-to-machine endpoint. No browser-origin requests or cookie fallback.
  if (req.headers.origin !== undefined) fail(403, "agent_browser_origin_forbidden");
  const session = await authenticateAgent(req.headers);
  if (url.search) fail(400, "agent_query_not_supported");
  return withWorkspace(session.tenantId, async () => {
    if (req.method === "GET" && url.pathname === "/agent/context") {
      const company = await one("SELECT id,name,locale FROM tenants WHERE id=$1", [session.tenantId]);
      return sendJson(res, 200, { company, timezone: "Europe/Vienna", server_time: new Date().toISOString(),
        scopes: session.scopes, connection_id: session.agentTokenId });
    }
    if (req.method === "GET" && url.pathname === "/agent/tools") {
      return sendJson(res, 200, { tools: discoverTools(session) });
    }
    const hit = /^\/agent\/tools\/([a-z][a-z0-9_]{0,99})$/.exec(url.pathname);
    if (req.method !== "POST" || !hit) fail(404, "not_found");
    if (!(req.headers["content-type"] ?? "").toLowerCase().startsWith("application/json")) fail(415, "json_required");
    const result = await execute(hit[1], await readJson(req), session, req.headers, ip, routes);
    return sendJson(res, 200, result);
  });
}
