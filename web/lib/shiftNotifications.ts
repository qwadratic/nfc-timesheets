import { apiFetch } from '@/lib/api'

/**
 * TASK-380 — "Schicht beendet". One row per shift a WORKER ended on the phone in the last
 * seven days (server/routes/shift-notifications.js). Admin-entered shifts never appear.
 *
 * `ended_at` and `seen_at` are opaque microsecond cursors: send them back exactly as
 * received, never through `new Date()`, or the newest row comes back as new forever.
 */
export type ShiftNotification = {
  id: number
  client_uuid: string
  worker_name: string
  location_name: string
  start_time: string
  end_time: string
  auto_closed: boolean
  ended_at: string
  has_photo: boolean
  sample_count: number
  unread: boolean
}

export type ShiftNotificationFeed = {
  notifications: ShiftNotification[]
  unread_count: number
  seen_at: string | null
}

/** How often the header asks, while the tab is visible. */
export const SHIFT_NOTIFICATION_POLL_MS = 45_000

export function fetchShiftNotifications(signal?: AbortSignal): Promise<ShiftNotificationFeed> {
  return apiFetch<ShiftNotificationFeed>('/admin/shift-notifications', { signal })
}

/** Marks read up to the newest row the admin was SHOWN — never "now". */
export function markShiftNotificationsSeen(
  through: string,
  signal?: AbortSignal,
): Promise<ShiftNotificationFeed> {
  return apiFetch<ShiftNotificationFeed>('/admin/shift-notifications/seen', {
    method: 'POST',
    body: { through },
    signal,
  })
}

/**
 * The deep link the shifts page opens the evidence view (photo + GPS map) from. Contract
 * with app/shifts/page.tsx — owned there, not here.
 */
export function evidenceHref(clientUuid: string): string {
  return `/shifts/?evidence=${encodeURIComponent(clientUuid)}`
}
