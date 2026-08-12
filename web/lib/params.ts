import { isPeriod, type Period, type PeriodRange } from '@/lib/period'

/**
 * The URL parameter contract (backlog/docs/IA-AND-JTBD.md §5), validated at the boundary.
 *
 * `output: 'export'` (decision-16) means there are no dynamic routes, so a query string is
 * the ENTIRE deep-link vocabulary of this panel. That makes bad input a user-visible
 * problem rather than a 404, and it makes one failure mode dangerous above all others:
 *
 *   G4 — a well-formed but unknown filter value (`?worker=999`, a deactivated building's
 *   UUID) must show EVERY row plus a banner naming the value. It must NEVER render an
 *   empty table, because an empty table is indistinguishable from data loss, and a
 *   director already read one that way once (UX-AUDIT finding 8). A filter that silently
 *   matches nothing is a wrong answer wearing a right one's clothes.
 *
 * Everything here is a pure function of a query STRING, not of `window`, so scripts/check.mjs
 * runs it directly. `readSearch()` is the only thing that touches the browser.
 *
 * ponytail: hand-rolled validation over `URLSearchParams`, no schema library and notably
 * NOT `useSearchParams()` — under `output: 'export'` that drags every consuming page into a
 * build-time Suspense boundary for no benefit. Ceiling: params are unreadable during
 * prerender, hence G7 (the screen shows its loading state until they are parsed). Upgrade
 * path: `useSearchParams` + `Suspense` if Back-through-filters is ever asked for.
 */

/** G5: a UUID is 36 characters and an ISO instant is 24. Anything longer is junk. */
export const MAX_PARAM_LENGTH = 64

/** G8: ids are canonical lowercase 36-character UUIDs, never a slug (decision-21). */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

export function isUuid(value: string): boolean {
  return value.length <= MAX_PARAM_LENGTH && UUID.test(value)
}

/** Integer ≥ 1, in decimal, with no sign, padding or exponent. */
export function isRowId(value: string): boolean {
  return value.length <= MAX_PARAM_LENGTH && /^[1-9][0-9]*$/.test(value)
}

/** An ISO-8601 instant that round-trips. `new Date('2026')` parses; that is not an instant. */
export function isInstant(value: string): boolean {
  if (value.length > MAX_PARAM_LENGTH) return false
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return false
  }
  return !Number.isNaN(Date.parse(value))
}

/** `?state=` on /shifts/. `all` is the default and is a real member, not an absence. */
export const SHIFT_STATE_FILTERS = ['all', 'open', 'unresolved', 'resolved', 'complete'] as const
export type ShiftStateFilter = (typeof SHIFT_STATE_FILTERS)[number]

function isShiftStateFilter(value: string): value is ShiftStateFilter {
  return (SHIFT_STATE_FILTERS as readonly string[]).includes(value)
}

export const ALL = 'all'

/**
 * What the screen has to TELL the reader about the link they arrived on.
 *
 * `invalid` is G3 (a known param with a malformed value: fell back to the default, say so).
 * `unknownEntity` is G4 and is filled in by the SCREEN, not here, because only the screen
 * holds the rows that decide whether an id exists.
 */
export type ShiftsParams = {
  /** Worker row id as a string, or `all`. */
  worker: string
  /** Location UUID, or `all`. */
  location: string
  state: ShiftStateFilter
  /** `null` when an explicit `from`/`to` pair won. */
  period: Period | null
  /** G3.1: absolute beats named — a money link must keep reproducing its own number. */
  range: PeriodRange | null
  /** Names of params that were present, known and malformed. G3. */
  invalid: readonly string[]
}

export const DEFAULT_SHIFTS_PARAMS: ShiftsParams = {
  worker: ALL,
  location: ALL,
  state: ALL,
  period: 'last30Days',
  range: null,
  invalid: [],
}

/**
 * Parse `/shifts/`'s query string. Unknown param NAMES are ignored silently (G2: an
 * `?fbclid=` from a chat unfurl must not break a screen); known names with bad values fall
 * back to the default AND are reported (G3).
 */
export function parseShiftsParams(search: string): ShiftsParams {
  const q = new URLSearchParams(search)
  const invalid: string[] = []

  const pick = <T>(name: string, fallback: T, parse: (raw: string) => T | null): T => {
    const raw = q.get(name)
    if (raw === null) return fallback
    if (raw.length > MAX_PARAM_LENGTH) {
      invalid.push(name)
      return fallback
    }
    const value = parse(raw)
    if (value === null) {
      invalid.push(name)
      return fallback
    }
    return value
  }

  const workerValue = pick<string>('worker', ALL, (raw) =>
    raw === ALL || isRowId(raw) ? raw : null,
  )
  const locationValue = pick<string>('location', ALL, (raw) =>
    raw === ALL || isUuid(raw) ? raw : null,
  )
  const stateValue = pick<ShiftStateFilter>('state', ALL, (raw) =>
    isShiftStateFilter(raw) ? raw : null,
  )
  const periodValue = pick<Period>('period', 'last30Days', (raw) => (isPeriod(raw) ? raw : null))

  // G9: `from` and `to` come as a PAIR. One end alone is malformed, because a half-specified
  // pay period is exactly how a month-end number goes wrong quietly.
  const rawFrom = q.get('from')
  const rawTo = q.get('to')
  let range: PeriodRange | null = null
  if (rawFrom !== null || rawTo !== null) {
    if (rawFrom !== null && rawTo !== null && isInstant(rawFrom) && isInstant(rawTo)) {
      if (Date.parse(rawFrom) < Date.parse(rawTo)) range = { from: rawFrom, to: rawTo }
    }
    if (range === null) {
      if (rawFrom !== null) invalid.push('from')
      if (rawTo !== null) invalid.push('to')
    }
  }

  return {
    worker: workerValue,
    location: locationValue,
    state: stateValue,
    // Absolute wins (§3.1): a named period re-resolves tomorrow and stops reproducing the
    // number the director is standing there defending.
    period: range === null ? periodValue : null,
    range,
    invalid,
  }
}

/** Build `/shifts/?…` for a cross-link. Absolute range when given, named period otherwise. */
export function shiftsHref(options: {
  worker?: number
  location?: string
  state?: ShiftStateFilter
  period?: Period
  range?: PeriodRange
}): string {
  const q = new URLSearchParams()
  if (options.worker !== undefined) q.set('worker', String(options.worker))
  if (options.location !== undefined) q.set('location', options.location)
  if (options.state !== undefined && options.state !== ALL) q.set('state', options.state)
  if (options.range?.from != null && options.range.to != null) {
    q.set('from', options.range.from)
    q.set('to', options.range.to)
  } else if (options.period !== undefined) {
    q.set('period', options.period)
  }
  const query = q.toString()
  return query === '' ? '/shifts/' : `/shifts/?${query}`
}

/** The browser's current query string, or `''` during prerender. G7 depends on this. */
export function readSearch(): string {
  return typeof window === 'undefined' ? '' : window.location.search
}

/**
 * G6: filter changes are written back with `replaceState`, never `pushState`. The URL stays
 * copy-paste-shareable and Back still means „the screen I came from" — which is the entire
 * point of a context-carrying link.
 */
export function writeSearch(next: URLSearchParams): void {
  if (typeof window === 'undefined') return
  const query = next.toString()
  window.history.replaceState(null, '', query === '' ? window.location.pathname : `?${query}`)
}
