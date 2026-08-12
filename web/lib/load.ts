import type { ErrorKey } from '@/lib/locale'

/**
 * `null` is not a state.
 *
 * Every admin screen used to hold `data: T | null` next to `error: ErrorKey | null` and
 * render them independently. Those two nullables have four combinations and only three of
 * them mean anything, so the fourth — data still null AND an error set — rendered a red
 * line followed by „Wird geladen…" that never went away. That was UX-AUDIT finding 1, and
 * it was live on all eleven screens after any 500.
 *
 * A discriminated union makes the fourth combination unrepresentable. `loadOf` is the
 * bridge for screens that still keep the two `useState` cells (they need the old snapshot
 * during a refetch, so collapsing them is a bigger change than this iteration wants) —
 * ponytail: the pair stays, but nothing may READ it except through here. Ceiling: a screen
 * can still forget to call `loadOf`. Upgrade path: one `useLoad` hook per screen, once the
 * refetch-keeps-old-data question is settled.
 */
export type Load<T> =
  | { readonly state: 'loading' }
  | { readonly state: 'ready'; readonly data: T }
  | { readonly state: 'error'; readonly key: ErrorKey }

/**
 * Error WINS over loading. That order is the whole fix: a request that failed is not still
 * in flight, and saying it is, forever, is how a director sat looking at a spinner that
 * would never resolve while the answer („der Server antwortet nicht") was already known.
 */
export function loadOf<T>(data: T | null, error: ErrorKey | null): Load<T> {
  if (error !== null) return { state: 'error', key: error }
  if (data === null) return { state: 'loading' }
  return { state: 'ready', data }
}
