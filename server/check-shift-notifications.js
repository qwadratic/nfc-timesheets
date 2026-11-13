// TASK-380: "Schicht beendet" feed. Real PostgreSQL + HTTP, called from check-workspaces.js
// with two companies (a, b), each with one admin, one worker and one verified zone. Must run
// while both companies' shift policy is still the default (no photo required to close).
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const CURSOR_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;

export async function checkShiftNotifications({ call, owner, a, b, hashToken }) {
  const feed = (cookie, since) => call(`/admin/shift-notifications${since ? `?since=${encodeURIComponent(since)}` : ""}`, { cookie });
  const seen = (cookie, through) => call("/admin/shift-notifications/seen", { cookie, body: { through } });

  // Who may ask: a company admin only. A worker cookie, no cookie and junk are refused.
  assert.equal((await feed(a.workerCookie)).status, 401, "worker cannot read the admin feed");
  assert.equal((await feed(undefined)).status, 401);
  assert.equal((await seen(a.workerCookie, new Date().toISOString())).status, 401, "worker cannot mark seen");
  assert.equal((await feed(a.cookie, "yesterday")).status, 400);
  assert.equal((await call("/admin/shift-notifications/seen", { cookie: a.cookie, body: {} })).status, 400);

  // After the 90-minute shift check-workspaces already closed (ended 30 min ago).
  // A worker ends a shift on the phone -> exactly that shift heads company A's feed.
  const uuid = randomUUID();
  const start = new Date(Date.now() - 25 * 60000).toISOString();
  assert.equal((await call("/shifts/open", { cookie: a.workerCookie, body: { location_uuid: a.zone.id, client_uuid: uuid, start_time: start } })).status, 201);
  const end = new Date(Date.now() - 5 * 60000).toISOString();
  assert.equal((await call("/shifts/close", { cookie: a.workerCookie, body: { client_uuid: uuid, end_time: end } })).status, 200);

  const first = await feed(a.cookie);
  assert.equal(first.status, 200, JSON.stringify(first.data));
  const item = first.data.notifications[0];
  assert.equal(item.client_uuid, uuid);
  assert.equal(item.worker_name, a.worker.name);
  assert.equal(item.location_name, a.location.name);
  assert.equal(new Date(item.start_time).toISOString(), start);
  assert.equal(new Date(item.end_time).toISOString(), end);
  assert.equal(item.has_photo, false);
  assert.equal(item.sample_count, 0);
  assert.equal(item.unread, true);
  assert.match(item.ended_at, CURSOR_RE, "cursor keeps Postgres microseconds");
  assert.ok(first.data.unread_count >= 1);

  // Tenant isolation: company B never sees company A's shift, and vice versa.
  for (const [self, other] of [[a, b], [b, a]]) {
    const own = await feed(self.cookie);
    assert.equal(own.status, 200);
    assert.ok(own.data.notifications.every((n) => n.worker_name === self.worker.name), "only own company's workers");
    assert.ok(!JSON.stringify(own.data).includes(other.location.name));
  }
  assert.ok(!(await feed(b.cookie)).data.notifications.some((n) => n.client_uuid === uuid));

  // An admin's own entry is not news to the admin: POST /admin/shifts never notifies.
  const manual = await call("/admin/shifts", { cookie: a.cookie, body: { worker_id: a.worker.id, location_id: a.location.id,
    start_time: new Date(Date.now() - 30 * 3600000).toISOString(), end_time: new Date(Date.now() - 29 * 3600000).toISOString() } });
  assert.equal(manual.status, 201, JSON.stringify(manual.data));
  assert.ok(!(await feed(a.cookie)).data.notifications.some((n) => n.id === manual.data.shift.id));

  // The exact cursor returns nothing newer — it would if microseconds were lost in transit.
  const since = await feed(a.cookie, item.ended_at);
  assert.equal(since.status, 200);
  assert.deepEqual(since.data.notifications, []);

  // Marking seen clears A's badge, not B's, and never moves backwards.
  const unreadB = (await feed(b.cookie)).data.unread_count;
  const marked = await seen(a.cookie, item.ended_at);
  assert.equal(marked.status, 200, JSON.stringify(marked.data));
  assert.equal(marked.data.unread_count, 0);
  assert.equal(marked.data.seen_at, item.ended_at);
  assert.equal(marked.data.notifications[0].unread, false);
  assert.equal((await feed(b.cookie)).data.unread_count, unreadB, "another company's read mark is untouched");
  assert.equal((await seen(a.cookie, "2020-01-01T00:00:00Z")).data.seen_at, item.ended_at, "the mark only moves forward");

  // decision-80: a platform operator inside company A reads the feed but does not clear the
  // company admin's badge.
  const later = randomUUID();
  assert.equal((await call("/shifts/open", { cookie: a.workerCookie, body: { location_uuid: a.zone.id, client_uuid: later, start_time: new Date(Date.now() - 60000).toISOString() } })).status, 201);
  assert.equal((await call("/shifts/close", { cookie: a.workerCookie, body: { client_uuid: later, end_time: new Date().toISOString() } })).status, 200);
  const adminA = (await owner.query("SELECT id FROM admins WHERE tenant_id=$1 AND role='admin' ORDER BY id LIMIT 1", [a.id])).rows[0].id;
  const platformId = (await owner.query("SELECT id FROM admins WHERE role='superadmin' ORDER BY id LIMIT 1")).rows[0].id;
  const token = "e".repeat(64);
  await owner.query("INSERT INTO sessions (token,admin_id,expires_at,impersonator_admin_id) VALUES ($1,$2,now()+interval '1 hour',$3)", [hashToken(token), adminA, platformId]);
  const inside = `ts_session=${token}`;
  const entered = await feed(inside);
  assert.equal(entered.data.notifications[0].client_uuid, later);
  assert.equal((await seen(inside, entered.data.notifications[0].ended_at)).data.unread_count, 1, "impersonation does not mark read");
  assert.equal((await feed(a.cookie)).data.unread_count, 1);
  await owner.query("DELETE FROM sessions WHERE token=$1", [hashToken(token)]);

  await owner.query("DELETE FROM shifts WHERE client_uuid = ANY($1) OR id=$2", [[uuid, later], manual.data.shift.id]);
  await owner.query("UPDATE admins SET shift_notifications_seen_at=NULL WHERE id=$1", [adminA]);
  console.log("check-shift-notifications: PASS (worker-ended feed, admin-only, tenant isolation, admin entries silent, microsecond cursor, per-admin read mark, impersonation read-only)");
}
