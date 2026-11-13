-- TASK-380: "Schicht beendet" in the web admin.
--
-- shifts.worker_ended_at is WHEN the worker's phone ended the shift (server clock), set by
-- POST /shifts/close and POST /shifts/:id/resolve only. It is NOT end_time: end_time is the
-- worker's claimed instant and may be hours old when an offline queue syncs, so it cannot be
-- a polling cursor. Admin-entered and admin-corrected shifts never set it — the admin does
-- not need to be told about their own edit. NULL for all history: no backfill, nobody is
-- notified about last year.
--
-- admins.shift_notifications_seen_at is the per-admin "read up to here" mark. NULL = never
-- opened the feed; the feed window (7 days) bounds what that counts as unread.
--
-- Both tables already carry RLS (022); new columns inherit it. Additive, metadata-only on
-- PG 16. NO BEGIN/COMMIT — migrate.js runs each file with `psql -1`.
ALTER TABLE shifts ADD COLUMN worker_ended_at TIMESTAMPTZ;
CREATE INDEX shifts_worker_ended_idx ON shifts (tenant_id, worker_ended_at DESC)
  WHERE worker_ended_at IS NOT NULL;

ALTER TABLE admins ADD COLUMN shift_notifications_seen_at TIMESTAMPTZ;
