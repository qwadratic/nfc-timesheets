// TASK-380: "Schicht beendet" — the admin is told when a worker ends a shift.
//
// A FEED, not a push channel: the web admin polls GET every ~45 s while its tab is visible
// (no websockets, no browser push — nothing new to run on the one VM, decision-16). The
// source of truth is shifts.worker_ended_at (migration 030), stamped only by the worker's
// own close/resolve, so an admin's own edit never notifies anyone.
//
// CURSORS ARE MICROSECOND TEXT, not JS Dates. Postgres keeps microseconds, a JS Date keeps
// milliseconds; a cursor round-tripped through Date would sit up to 999 µs BEFORE the row it
// came from, and that row would come back as "new" (and stay "unread") for ever. The text is
// passed back to Postgres untouched as a bound parameter, never spliced into SQL.
//
// Tenant scope is RLS (the handler runs inside withWorkspace); the per-admin read mark is
// session.adminId. During a superadmin impersonation (decision-80) the read mark is NOT
// written: a platform operator looking around must not clear the company admin's badge.
import { all, one } from "../lib/db.js";
import { fail } from "../lib/http.js";
import * as v from "../lib/validate.js";

const WINDOW = "7 days";
const LIMIT = 20;
const CURSOR = (col) => `to_char(${col} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;

function cursorParam(value, field) {
  if (value === null || value === undefined || value === "") return null;
  v.rangeBound(value, field); // shape + sanity only; the raw string keeps its microseconds
  return value.trim();
}

async function feed(adminId, since) {
  const admin = await one(
    `SELECT ${CURSOR("shift_notifications_seen_at")} AS seen_at FROM admins WHERE id = $1`,
    [adminId],
  );
  const seenAt = admin?.seen_at ?? null;
  const notifications = await all(
    `SELECT s.id, s.client_uuid, w.name AS worker_name, l.name AS location_name,
            s.start_time, s.end_time, s.auto_closed,
            ${CURSOR("s.worker_ended_at")} AS ended_at,
            (s.proof_id IS NOT NULL) AS has_photo,
            (SELECT count(*)::int FROM shift_locations sl WHERE sl.shift_id = s.id) AS sample_count,
            s.worker_ended_at > COALESCE($2::timestamptz, '-infinity') AS unread
       FROM shifts s
       JOIN workers w ON w.id = s.worker_id
       JOIN locations l ON l.id = s.location_id
      WHERE s.worker_ended_at > GREATEST(now() - interval '${WINDOW}', COALESCE($1::timestamptz, '-infinity'))
      ORDER BY s.worker_ended_at DESC, s.id DESC
      LIMIT ${LIMIT}`,
    [since, seenAt],
  );
  const counted = await one(
    `SELECT count(*)::int AS n FROM shifts
      WHERE worker_ended_at > GREATEST(now() - interval '${WINDOW}', COALESCE($1::timestamptz, '-infinity'))`,
    [seenAt],
  );
  return { notifications, unread_count: counted.n, seen_at: seenAt };
}

/** GET /admin/shift-notifications[?since=<ended_at cursor>] -> newest first, at most 20. */
async function list({ query, session }) {
  const since = cursorParam(query.get("since"), "since");
  return { status: 200, body: await feed(session.adminId, since) };
}

/**
 * POST /admin/shift-notifications/seen {through: <ended_at cursor>} -> marks read up to the
 * newest item the admin was actually SHOWN, never "now": a shift that ended between the last
 * poll and the click stays unread. The mark only moves forward and never past now().
 */
async function markSeen({ body, session }) {
  const through = cursorParam(body?.through, "through");
  if (through === null) fail(400, "invalid_field", "through");
  if (!session.impersonator) {
    await one(
      `UPDATE admins
          SET shift_notifications_seen_at = GREATEST(COALESCE(shift_notifications_seen_at, '-infinity'),
                                                     LEAST($2::timestamptz, now()))
        WHERE id = $1 RETURNING id`,
      [session.adminId, through],
    );
  }
  return { status: 200, body: await feed(session.adminId, null) };
}

export const shiftNotificationRoutes = [
  { method: "GET", path: "/admin/shift-notifications", auth: "admin", handler: list },
  { method: "POST", path: "/admin/shift-notifications/seen", auth: "admin", handler: markSeen },
];
