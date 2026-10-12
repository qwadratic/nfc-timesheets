// Real HTTP + PostgreSQL verification; uses a disposable schema and restricted RLS role.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import pg from "pg";
import { grantWorkspaceTestRole } from "./db/workspace-test-db.js";

const database = process.env.DATABASE_URL;
if (!database || !["127.0.0.1", "localhost", "[::1]"].includes(new URL(database).hostname)) {
  throw new Error("Agent verification requires an explicit loopback PostgreSQL URL");
}
const schema = `agent_check_${process.pid}`;
const owner = new pg.Client({ connectionString: database });
await owner.connect();
let server;
let runtimeRole;
let pool;
try {
  await owner.query(`CREATE SCHEMA ${schema}`);
  await owner.query(`SET search_path TO ${schema}`);
  await owner.query("SELECT set_config('app.system','on',false),set_config('app.tenant_id','1',false)");
  const migrations = new URL("./db/migrations/", import.meta.url);
  for (const file of readdirSync(migrations).filter((name) => name.endsWith(".sql")).sort()) {
    await owner.query(readFileSync(new URL(file, migrations), "utf8"));
  }
  runtimeRole = await grantWorkspaceTestRole(owner, schema);
  const scoped = new URL(database);
  scoped.searchParams.set("options", `-c search_path=${schema} -c role=${runtimeRole}`);
  process.env.DATABASE_URL = scoped.toString();
  process.env.APP_KEY = "local-agent-check";
  // Never contact paid messaging/geocoding services, even if the caller has credentials.
  for (const name of Object.keys(process.env)) {
    if (name.startsWith("TWILIO_") || name === "GOOGLE_GEOCODING_KEY") delete process.env[name];
  }
  delete process.env.SENTRY_DSN;
  ({ pool } = await import("./lib/db.js"));
  const { createAgentAccess, listAgentAccess, revokeAgentAccess } = await import("./agent/auth.js");
  const { hashPassword, hashToken } = await import("./lib/auth.js");
  const password = "Agent-test-2026!";
  const passwordHash = await hashPassword(password);
  const companies = [];
  for (const label of ["a", "b"]) {
    const tenant = (await owner.query("INSERT INTO tenants(name) VALUES($1) RETURNING id", [`Company ${label}`])).rows[0];
    const admin = (await owner.query("INSERT INTO admins(email,password_hash,tenant_id,role) VALUES($1,$2,$3,'admin') RETURNING id", [`${label}@agent.test`, passwordHash, tenant.id])).rows[0];
    const token = await createAgentAccess({ tenantId: tenant.id, adminId: admin.id, name: `Agent ${label}`, write: true });
    companies.push({ tenant: tenant.id, admin: admin.id, token });
  }
  const [a, b] = companies;
  const read = await createAgentAccess({ tenantId: a.tenant, adminId: a.admin, name: "Read only" });
  assert.deepEqual(read.scopes, ["read"]);
  const stored = (await owner.query("SELECT token_hash FROM agent_tokens WHERE id=$1", [a.token.id])).rows[0];
  assert.equal(stored.token_hash, hashToken(a.token.token));
  assert.ok(!JSON.stringify(await listAgentAccess(a.tenant)).includes(a.token.token));
  assert.ok(!JSON.stringify(await listAgentAccess(a.tenant)).includes(stored.token_hash));
  assert.ok((await listAgentAccess(a.tenant)).every((token) => token.tenant_id === a.tenant));
  await assert.rejects(createAgentAccess({ tenantId: a.tenant, adminId: b.admin, name: "Foreign" }), { status: 400 });
  await assert.rejects(revokeAgentAccess(a.tenant, b.token.id), { status: 404 });
  const platform = (await owner.query("INSERT INTO admins(email,password_hash,tenant_id,role) VALUES('platform@agent.test',$1,0,'superadmin') RETURNING id", [passwordHash])).rows[0];
  await assert.rejects(createAgentAccess({ tenantId: 0, adminId: platform.id, name: "Platform" }), { status: 400 });
  const flags = (await owner.query("INSERT INTO admins(email,password_hash,tenant_id,role) VALUES('flags@agent.test',$1,$2,'flags') RETURNING id", [passwordHash, a.tenant])).rows[0];
  await assert.rejects(createAgentAccess({ tenantId: a.tenant, adminId: flags.id, name: "Flags" }), { status: 400 });

  const { createServer } = await import("./server.js");
  server = createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function call(path, { token, body, cookie } = {}) {
    const response = await fetch(base + path, { method: body ? "POST" : "GET", headers: {
      "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}), ...(cookie ? { cookie } : {}),
    }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, data: await response.json(), cookie: response.headers.get("set-cookie")?.split(";")[0] };
  }
  const exercised = new Set();
  async function invoke(token, name, args = {}, requestId) {
    exercised.add(name);
    const response = await call(`/agent/tools/${name}`, { token, body: { arguments: args, ...(requestId ? { request_id: requestId } : {}) } });
    if (response.status !== 200) return response;
    assert.ok(Number.isInteger(response.data.status));
    return { status: response.data.status, data: response.data.result, replayed: response.data.replayed };
  }
  assert.equal((await call("/agent/tools")).status, 401);
  assert.equal((await call("/agent/context", { token: "invalid" })).status, 401);
  const discovery = await call("/agent/tools", { token: a.token.token });
  assert.equal(discovery.status, 200, JSON.stringify(discovery));
  const names = discovery.data.tools.map((tool) => tool.name);
  const readDiscovery = await call("/agent/tools", { token: read.token });
  assert.ok(readDiscovery.data.tools.every((tool) => tool.annotations.readOnlyHint));
  assert.equal(new Set(names).size, names.length);
  for (const name of ["get_company_data", "save_worker", "save_location", "create_assignment", "get_earnings_summary"]) assert.ok(names.includes(name), name);
  for (const tool of discovery.data.tools) {
    assert.ok(tool.description.length > 20, tool.name);
    assert.equal(tool.inputSchema.additionalProperties, false, tool.name);
  }
  const context = await call("/agent/context", { token: a.token.token });
  assert.equal(context.status, 200, JSON.stringify(context));
  assert.ok(JSON.stringify(context.data).includes("Company a"));
  assert.ok(!JSON.stringify(context.data).includes(a.token.token));
  assert.equal((await invoke(a.token.token, "not_a_tool")).status, 404);
  assert.equal((await invoke(a.token.token, "get_company_data", { tenant_id: b.tenant })).status, 400);
  assert.equal((await invoke(a.token.token, "save_worker", { name: "Missing idempotency", hourly_rate_cents: 1500 })).status, 400);
  assert.equal((await invoke(read.token, "save_worker", { name: "Forbidden", hourly_rate_cents: 1500 }, randomUUID())).status, 403);
  assert.equal((await invoke(a.token.token, "save_worker", { name: "Bad rate", hourly_rate_cents: 0 }, randomUUID())).status, 400);

  for (const company of companies) {
    const args = { name: `Anna ${company.tenant}`, hourly_rate_cents: 1500 };
    const requestId = randomUUID();
    const concurrent = await Promise.all([1, 2].map(() => invoke(company.token.token, "save_worker", args, requestId)));
    assert.ok(concurrent.some((result) => result.status === 201), JSON.stringify(concurrent));
    assert.ok(concurrent.every((result) => result.status === 201 || (result.status === 409 && result.data.error === "operation_pending")), JSON.stringify(concurrent));
    const results = [concurrent.find((result) => result.status === 201), await invoke(company.token.token, "save_worker", args, requestId)];
    assert.ok(results.every((result) => result.status === 201), JSON.stringify(results));
    assert.equal(results[0].data.worker.id, results[1].data.worker.id, "concurrent retries must not create duplicates");
    assert.deepEqual(results.map((result) => result.replayed).sort(), [false, true]);
    company.worker = results[0].data.worker;
    assert.equal((await invoke(company.token.token, "save_worker", { ...args, name: "Changed payload" }, requestId)).status, 409);
    const location = await invoke(company.token.token, "save_location", { name: `Haus ${company.tenant}`, slug: "same-slug" }, randomUUID());
    assert.equal(location.status, 201, JSON.stringify(location));
    company.location = location.data.location;
  }
  for (const [self, other] of [[a, b], [b, a]]) {
    const roster = await invoke(self.token.token, "get_company_data");
    assert.equal(roster.status, 200);
    assert.deepEqual(roster.data.workers.map((worker) => worker.id), [self.worker.id]);
    assert.deepEqual(roster.data.locations.map((location) => location.id), [self.location.id]);
    assert.equal((await invoke(self.token.token, "save_worker", { id: other.worker.id, name: "Foreign overwrite", hourly_rate_cents: 1 }, randomUUID())).status, 404);
    assert.equal((await invoke(self.token.token, "deactivate_location", { id: other.location.id }, randomUUID())).status, 404);
    const start = new Date(Date.now() + 86_400_000);
    const end = new Date(start.getTime() + 3_600_000);
    const plan = { id: randomUUID(), worker_id: self.worker.id, location_id: self.location.id, starts_at: start.toISOString(), ends_at: end.toISOString() };
    assert.equal((await invoke(self.token.token, "create_assignment", { ...plan, location_id: other.location.id }, randomUUID())).status, 404);
    const created = await invoke(self.token.token, "create_assignment", plan, randomUUID());
    assert.equal(created.status, 201, JSON.stringify(created));
    self.assignment = created.data.assignment;
    assert.equal((await invoke(self.token.token, "create_assignment", { ...plan, id: randomUUID() }, randomUUID())).status, 409);
    const shifts = await invoke(self.token.token, "list_assignments", { from: start.toISOString(), to: end.toISOString() });
    assert.equal(shifts.data.assignments.length, 1);
    const actual = await invoke(self.token.token, "create_actual_shift", { worker_id: self.worker.id, location_id: self.location.id, start_time: new Date(Date.now() - 7_200_000).toISOString(), end_time: new Date(Date.now() - 1_800_000).toISOString() }, randomUUID());
    assert.equal(actual.status, 201, JSON.stringify(actual));
    self.shift = actual.data.shift;
    const earnings = await invoke(self.token.token, "get_earnings_summary", { from: new Date(Date.now() - 86_400_000).toISOString(), to: end.toISOString() });
    assert.equal(earnings.status, 200, JSON.stringify(earnings));
    assert.equal(earnings.data.workers[0].estimated_cents, 2250, "actual 90 min at 15 EUR; future planned hour excluded");
  }
  assert.equal((await invoke(read.token, "get_company_data")).status, 200);
  const { createBridge } = await import("../tools/agent-mcp.mjs");
  const bridge = createBridge({ url: base, token: a.token.token });
  let rpcId = 0;
  const rpc = (method, params = {}) => bridge({ jsonrpc: "2.0", id: ++rpcId, method, params });
  const initialized = await rpc("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "integration-test", version: "1" } });
  assert.ok(initialized.result.instructions.includes("Company a"));
  await bridge({ jsonrpc: "2.0", method: "notifications/initialized" });
  assert.equal((await rpc("tools/list")).result.tools.length, names.length);
  const requestId = randomUUID();
  const codeCall = { name: "issue_worker_enrolment_code", arguments: { id: a.worker.id, request_id: requestId } };
  const codeReply = await rpc("tools/call", codeCall);
  assert.equal(codeReply.result.isError, false, JSON.stringify(codeReply));
  const codeResult = JSON.parse(codeReply.result.content[0].text);
  assert.ok(codeResult.result.code);
  const repeatedCode = JSON.parse((await rpc("tools/call", codeCall)).result.content[0].text);
  assert.equal(repeatedCode.result.code, codeResult.result.code);
  assert.equal(repeatedCode.replayed, true);
  exercised.add(codeCall.name);
  const cache = (await owner.query("SELECT * FROM agent_tool_calls WHERE token_id=$1 AND request_id=$2", [a.token.id, requestId])).rows[0];
  assert.ok(!JSON.stringify(cache).includes(codeResult.result.code));
  assert.ok(!JSON.stringify(cache).includes(a.token.token));
  assert.equal(Number((await owner.query("SELECT count(*) FROM action_log WHERE actor_type='agent' AND target_id=$1", [requestId])).rows[0].count), 1);
  const forbiddenMcp = await rpc("tools/call", { name: "save_worker", arguments: { id: b.worker.id, name: "Foreign", hourly_rate_cents: 100, request_id: randomUUID() } });
  assert.equal(forbiddenMcp.result.isError, true);
  const overlapArgs = { worker_id: a.worker.id, location_id: a.location.id, start_time: a.shift.start_time, end_time: a.shift.end_time };
  const failedId = randomUUID();
  for (let attempt = 0; attempt < 2; attempt++) assert.equal((await invoke(a.token.token, "create_actual_shift", overlapArgs, failedId)).status, 409);
  assert.equal((await owner.query("SELECT state FROM agent_tool_calls WHERE token_id=$1 AND request_id=$2", [a.token.id, failedId])).rows[0].state, "failed");
  const pendingId = randomUUID();
  const pendingArgs = { hourly_rate_cents: 1500, name: "Never created" };
  await owner.query("INSERT INTO agent_tool_calls(tenant_id,token_id,request_id,tool_name,arguments_hash) VALUES($1,$2,$3,'save_worker',$4)", [a.tenant, a.token.id, pendingId, createHash("sha256").update(JSON.stringify(pendingArgs)).digest("hex")]);
  const pending = await invoke(a.token.token, "save_worker", pendingArgs, pendingId);
  assert.equal(pending.status, 409);
  assert.equal(pending.data.error, "operation_pending");
  assert.equal(Number((await owner.query("SELECT count(*) FROM workers WHERE name='Never created'")).rows[0].count), 0);

  // Exercise every business capability against real handlers, including no-send/no-key paths.
  async function business(name, args = {}, expected) {
    const descriptor = discovery.data.tools.find((tool) => tool.name === name);
    const result = await invoke(a.token.token, name, args, descriptor.annotations.readOnlyHint ? undefined : randomUUID());
    assert.ok(expected ? expected.includes(result.status) : result.status >= 200 && result.status < 300, `${name}: ${JSON.stringify(result)}`);
    return result.data;
  }
  await business("update_company", { name: "Company a updated", locale: "de" });
  const client = (await business("save_client", { name: "Customer" })).client;
  const contact = (await business("save_contact", { client_id: client.id, name: "Contact", email: "contact@agent.test" })).contact;
  const inventory = (await business("save_inventory_item", { name: "Soap", kind: "product", unit_cost_cents: 150 })).item;
  const operator = (await business("create_operator", { name: "Operator", phone: "+436641111111" })).operator;
  const zone = (await owner.query("INSERT INTO zones(tenant_id,location_id,name,verified_at) VALUES($1,$2,'Entrance',now()) RETURNING id", [a.tenant, a.location.id])).rows[0];
  await business("update_zone", { id: zone.id, location_id: a.location.id, name: "Entrance updated", area_sqm: 40 });
  const tag = randomUUID();
  await owner.query("INSERT INTO reported_tags(id,tenant_id,reported_by_operator_id) VALUES($1,$2,$3)", [tag, a.tenant, operator.id]);
  await business("resolve_tag_to_zone", { id: tag, zone_id: zone.id });
  await owner.query("UPDATE locations SET address='Testgasse 1, Wien' WHERE id=$1", [a.location.id]);
  const geocoded = await business("geocode_location", { id: a.location.id });
  assert.equal(geocoded.location.geocode_status, "no_key");
  const contract = await business("create_contract", { id: a.location.id, monthly_contract_cents: 10000, valid_from: "2026-01-01" });
  const contracts = await business("list_contracts", { id: a.location.id });
  assert.ok(contracts.contracts.length > 0);
  await business("delete_contract", { id: contract.contract.id });
  await business("save_location", { id: a.location.id, name: a.location.name, slug: a.location.slug, client_id: client.id, contact_id: contact.id });
  const portal = await business("create_portal_grant", { contact_id: contact.id, location_id: a.location.id });
  const grant = (await owner.query("SELECT token_hash FROM portal_grants WHERE tenant_id=$1", [a.tenant])).rows[0];
  assert.ok(portal.token || portal.url || portal.portal_url, JSON.stringify(portal));
  await business("revoke_portal_grant", { token_hash: grant.token_hash });
  const material = (await owner.query("INSERT INTO material_requests(tenant_id,worker_id,location_id,body) VALUES($1,$2,$3,'Soap') RETURNING id", [a.tenant, a.worker.id, a.location.id])).rows[0];
  await business("update_material_request", { id: material.id, status: "approved", quantity: 2 });
  await business("correct_actual_shift", { id: a.shift.id, end_time: a.shift.end_time });
  const period = { from: "2026-01-01T00:00:00Z", to: "2026-02-01T00:00:00Z" };
  await business("record_revenue", { id: a.location.id, month: "2026-01", amount_cents: 10000 });
  await business("record_revenue_bulk", { entries: [{ location_id: a.location.id, month: "2026-01", amount_cents: 12000 }] });
  await business("list_revenue", period);
  await business("get_profit_and_loss", period);
  await business("get_building_analytics", { ...period, months: 2 });
  await business("retract_revenue", { id: a.location.id, month: "2026-01" });
  await business("set_company_setting", { key: "pl_margin_baseline_bp", value: 1500 });
  await business("clear_company_setting", { key: "pl_margin_baseline_bp" });
  const changedPlan = (await business("update_assignment", { id: a.assignment.id, version: a.assignment.version, worker_id: a.worker.id, location_id: a.location.id, starts_at: a.assignment.starts_at, ends_at: a.assignment.ends_at, note: "Updated" })).assignment;
  await business("cancel_assignment", { id: changedPlan.id, version: changedPlan.version });
  await business("get_sms_status");
  await business("set_worker_login_phone", { id: a.worker.id, phone: "+436642222222" });
  for (const [subject, id] of [["worker", a.worker.id], ["operator", operator.id]]) {
    await business(`set_${subject}_login_email`, { id, email: `${subject}@identity.agent.test` });
    await business(`remove_${subject}_login_email`, { id });
    // Force one collision inside the outer tool transaction. A savepoint must allow retry.
    await owner.query(`CREATE SEQUENCE ${subject}_collision`);
    await owner.query(`GRANT USAGE,SELECT ON SEQUENCE ${subject}_collision TO ${runtimeRole}`);
    await owner.query(`CREATE FUNCTION ${subject}_collision_once() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN IF nextval('${subject}_collision')=1 THEN RAISE unique_violation; END IF; RETURN NEW; END $$`);
    await owner.query(`CREATE TRIGGER collision_once BEFORE UPDATE OF enrolment_code_hash ON ${subject}s FOR EACH ROW EXECUTE FUNCTION ${subject}_collision_once()`);
    await business(`issue_${subject}_enrolment_code`, { id });
    assert.equal(Number((await owner.query(`SELECT last_value FROM ${subject}_collision`)).rows[0].last_value), 2);
    await owner.query(`DROP TRIGGER collision_once ON ${subject}s`);
    const sms = await business(`send_${subject}_enrolment_sms`, { id }, [503]);
    assert.equal(sms.error, "sms_not_configured", "must never send real SMS");
    await business(`revoke_${subject}_enrolment_code`, { id });
  }
  await business("remove_worker_login_phone", { id: a.worker.id });
  await business("deactivate_operator", { id: operator.id });
  await business("reactivate_operator", { id: operator.id });
  await business("deactivate_zone", { id: zone.id });
  await business("deactivate_inventory_item", { id: inventory.id });
  await business("deactivate_contact", { id: contact.id });
  await business("deactivate_client", { id: client.id });
  await business("deactivate_location", { id: a.location.id });
  await business("deactivate_worker", { id: a.worker.id });
  assert.deepEqual(names.filter((name) => !exercised.has(name)), [], "every advertised tool exercised");
  // Existing browser sessions remain independent from issued/revoked integration access.
  const login = await call("/admin/login", { body: { email: "a@agent.test", password } });
  assert.equal(login.status, 200, JSON.stringify(login));
  assert.equal((await call("/agent/tools", { cookie: login.cookie })).status, 401);
  await revokeAgentAccess(a.tenant, a.token.id);
  assert.equal((await call("/agent/tools", { token: a.token.token })).status, 401);
  assert.equal((await call("/admin/data", { cookie: login.cookie })).status, 200);
  await owner.query("UPDATE agent_tokens SET created_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE id=$1", [read.id]);
  assert.equal((await call("/agent/tools", { token: read.token })).status, 401);
  await owner.query("UPDATE admins SET role='flags' WHERE id=$1", [b.admin]);
  assert.equal((await call("/agent/tools", { token: b.token.token })).status, 401);
  await owner.query("UPDATE admins SET role='admin' WHERE id=$1", [b.admin]);
  await owner.query("UPDATE tenants SET active=false WHERE id=$1", [b.tenant]);
  assert.equal((await call("/agent/tools", { token: b.token.token })).status, 401);
  assert.equal(Number((await owner.query("SELECT count(*) FROM workers")).rows[0].count), 2);
  console.log(`check-agent: PASS (${names.length}/${names.length} tools exercised; MCP lifecycle, two-company isolation, read/write scopes, concurrent/failed/pending idempotency, encrypted secret replay, single audit, collision retry, schedule and actual earnings, token lifecycle, browser-session separation; SMS/geocoding safely unconfigured)`);
} finally {
  if (server) await new Promise((resolve) => server.close(resolve));
  if (pool) await pool.end();
  await owner.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
  if (runtimeRole) await owner.query(`DROP ROLE ${runtimeRole}`);
  await owner.end();
}
