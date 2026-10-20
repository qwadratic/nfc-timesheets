// decision-85 journeys: a platform administrator enters a company, acts inside it under
// audit, cannot take over its credentials, and leaves back to the platform.
import assert from "node:assert/strict";

export async function checkImpersonation({ base, owner, a, b, platform, password, hashPassword, hashToken }) {
  // Own helper: entering and leaving set TWO cookies, which the shared one cannot see.
  async function call(path, { cookies = [], body, method = body ? "POST" : "GET" } = {}) {
    const response = await fetch(base + path, { method, headers: {
      "content-type": "application/json", "x-app-key": process.env.APP_KEY,
      ...(cookies.length ? { cookie: cookies.join("; ") } : {}),
    }, body: body ? JSON.stringify(body) : undefined });
    const set = Object.fromEntries(response.headers.getSetCookie().map((line) => line.split(";")[0].split("=")));
    return { status: response.status, data: await response.json(), set };
  }
  const platformCookie = platform.cookie;

  const list = await call("/platform/workspaces", { cookies: [platformCookie] });
  assert.equal(list.data.workspaces.find((w) => w.id === a.id).admin_count, 1);

  // Only a platform session may enter; a company admin cannot enter another company.
  assert.equal((await call(`/platform/workspaces/${b.id}/enter`, { cookies: [a.cookie], body: {} })).status, 401);
  assert.equal((await call("/platform/workspaces/999999/enter", { cookies: [platformCookie], body: {} })).status, 409);
  const empty = (await owner.query("INSERT INTO tenants (name) VALUES ('No owner yet') RETURNING id")).rows[0];
  const refused = await call(`/platform/workspaces/${empty.id}/enter`, { cookies: [platformCookie], body: {} });
  assert.equal(refused.status, 409);
  assert.equal(refused.data.error, "no_company_admin");

  const entered = await call(`/platform/workspaces/${a.id}/enter`, { cookies: [platformCookie], body: {} });
  assert.equal(entered.status, 200, JSON.stringify(entered.data));
  assert.ok(entered.set.ts_session && entered.set.ts_session !== platformCookie.split("=")[1]);
  assert.equal(entered.set.ts_platform, platformCookie.split("=")[1], "platform session parked, not lost");
  const inside = [`ts_session=${entered.set.ts_session}`, `ts_platform=${entered.set.ts_platform}`];
  const ttl = new Date(entered.data.expires_at).getTime() - Date.now();
  assert.ok(ttl > 50 * 60_000 && ttl <= 60 * 60_000, "entered session is short-lived");

  const me = await call("/admin/session", { cookies: inside });
  assert.equal(me.data.admin.role, "admin");
  assert.equal(me.data.admin.tenant_id, a.id);
  assert.equal(me.data.admin.impersonator.email, "platform@example.test");
  assert.equal(me.data.admin.impersonator.company, "Clean A");
  const ordinary = await call("/admin/session", { cookies: [a.cookie] });
  assert.equal(ordinary.data.admin.impersonator, null);

  // Company scope exactly as the owner sees it, never the other company's.
  const data = await call("/admin/data", { cookies: inside });
  assert.deepEqual(data.data.workers.map((w) => w.id), [a.worker.id]);
  assert.equal((await call("/admin/workers", { cookies: inside, body: { id: b.worker.id, name: "Tampered", hourly_rate_cents: 1 } })).status, 404);
  assert.equal((await call("/platform/workspaces", { cookies: inside })).status, 401, "inside a company the platform routes are closed");

  const before = Number((await owner.query("SELECT count(*) FROM action_log WHERE tenant_id=$1 AND origin='superadmin'", [a.id])).rows[0].count);
  const saved = await call("/admin/workers", { cookies: inside, body: { name: "Hired by support", hourly_rate_cents: 1600 } });
  assert.equal(saved.status, 201, JSON.stringify(saved.data));
  const audit = (await owner.query(`SELECT actor_id, action, target_id FROM action_log
    WHERE tenant_id=$1 AND origin='superadmin' ORDER BY id`, [a.id])).rows;
  assert.equal(audit.length, before + 1);
  const platformId = String((await owner.query("SELECT id FROM admins WHERE email='platform@example.test'")).rows[0].id);
  assert.equal(String(audit.at(-1).actor_id), platformId);
  assert.equal(audit.at(-1).action, "POST /admin/workers");
  assert.ok(audit.some((row) => row.action === "impersonation.started"));

  // Credentials stay the company's own.
  const passwordChange = await call("/admin/password", { cookies: inside, body: { current_password: "x", new_password: "Something-new-1" } });
  assert.equal(passwordChange.status, 403);
  assert.equal(passwordChange.data.error, "impersonation_forbidden");

  // Leaving restores the platform session and kills the company one.
  assert.equal((await call("/admin/impersonation/exit", { cookies: [a.cookie], body: {} })).status, 409);
  const left = await call("/admin/impersonation/exit", { cookies: inside, body: {} });
  assert.equal(left.status, 200);
  assert.equal(left.data.restored, true);
  assert.equal(left.set.ts_session, platformCookie.split("=")[1]);
  assert.equal(left.set.ts_platform, "");
  assert.equal((await call("/admin/data", { cookies: inside })).status, 401, "company session revoked");
  assert.equal((await call("/platform/workspaces", { cookies: [platformCookie] })).status, 200, "platform session intact");
  assert.equal((await call("/admin/data", { cookies: [a.cookie] })).status, 200, "owner's own session untouched");
  assert.ok((await owner.query("SELECT 1 FROM action_log WHERE tenant_id=$1 AND action='POST /admin/impersonation/exit'", [a.id])).rows.length);

  // A forged platform cookie next to an entered session restores nothing.
  const again = await call(`/platform/workspaces/${a.id}/enter`, { cookies: [platformCookie], body: {} });
  const forged = await call("/admin/impersonation/exit", { cookies: [`ts_session=${again.set.ts_session}`, `ts_platform=${"f".repeat(64)}`], body: {} });
  assert.equal(forged.data.restored, false);
  assert.equal(forged.set.ts_session, "");

  // Signing out from inside signs the platform administrator out completely.
  const platformLogin = await call("/admin/login", { body: { email: "platform@example.test", password } });
  const fresh = `ts_session=${platformLogin.set.ts_session}`;
  const third = await call(`/platform/workspaces/${a.id}/enter`, { cookies: [fresh], body: {} });
  const out = await call("/admin/logout", { cookies: [`ts_session=${third.set.ts_session}`, `ts_platform=${third.set.ts_platform}`], body: {} });
  assert.equal(out.status, 200);
  assert.equal((await call("/platform/workspaces", { cookies: [fresh] })).status, 401, "parked platform session revoked on logout");

  // Removing the platform account ends every company session it opened.
  await owner.query("INSERT INTO admins (email,password_hash,tenant_id,role) VALUES ('support@example.test',$1,0,'superadmin')", [await hashPassword(password)]);
  const fourthLogin = await call("/admin/login", { body: { email: "support@example.test", password } });
  const fourth = await call(`/platform/workspaces/${a.id}/enter`, { cookies: [`ts_session=${fourthLogin.set.ts_session}`], body: {} });
  assert.equal((await call("/admin/data", { cookies: [`ts_session=${fourth.set.ts_session}`] })).status, 200);
  // Demoted into an ordinary company account: the entered session dies with the role...
  await owner.query("DELETE FROM sessions WHERE admin_id=(SELECT id FROM admins WHERE email='support@example.test')");
  await owner.query("UPDATE admins SET role='admin', tenant_id=$1 WHERE email='support@example.test'", [b.id]);
  assert.equal((await call("/admin/data", { cookies: [`ts_session=${fourth.set.ts_session}`] })).status, 401);
  // ...and deleting the account removes the row outright.
  await owner.query("DELETE FROM admins WHERE email='support@example.test'");
  assert.equal(Number((await owner.query("SELECT count(*) FROM sessions WHERE token=$1", [hashToken(fourth.set.ts_session)])).rows[0].count), 0);
  assert.equal((await call("/admin/data", { cookies: [`ts_session=${fourth.set.ts_session}`] })).status, 401);
  console.log("check-impersonation: PASS (enter, scope, audit, credential guard, exit, forged exit, logout, opener removal)");
}
