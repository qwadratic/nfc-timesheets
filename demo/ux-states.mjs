// UX-AUDIT state capture. Throwaway harness — the pattern of /tmp/mobshot.mjs:
// static file server for web/out + stubbed admin API returning CRAFTED payloads,
// driven by demo/cdp.mjs (no new dependency). NEVER points at production.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { launchChrome, attach, sleep } from '/Users/gerhardgustav/Desktop/ai-automations/hoiv/cleaning-timesheets/demo/cdp.mjs'

const ROOT = '/Users/gerhardgustav/Desktop/ai-automations/hoiv/cleaning-timesheets'
const OUT = path.join(ROOT, 'web/out')
const SHOTS = process.env.SHOT_DIR ?? path.join(ROOT, 'docs/media/states')
fs.mkdirSync(SHOTS, { recursive: true })

const LOC_A = 'c3c37d4a-ca0a-42c5-b248-9704b9907ec7'
const LOC_B = '1a2b3c4d-0000-4000-8000-000000000002'
const LOC_C = '1a2b3c4d-0000-4000-8000-000000000003'

// "now" for the fixtures. The harness runs on 2026-08-12; lastMonth = July 2026.
const iso = (s) => new Date(s).toISOString()

const WORKERS = [
  { id: 1, name: 'Bálint Kovács', email: 'balint@example.at', phone: '+43 660 1234567', hourly_rate_cents: 1450, active: true, created_at: iso('2026-06-01'), enrolment_code_expires_at: iso('2026-08-12T09:00:00Z'), enrolment_code_redeemed_at: null },
  { id: 2, name: 'Anna Nowak', email: 'anna@example.at', phone: null, hourly_rate_cents: 1600, active: true, created_at: iso('2026-06-02'), enrolment_code_expires_at: null, enrolment_code_redeemed_at: iso('2026-07-14T08:12:00Z') },
  { id: 3, name: 'Dragan Petrović', email: null, phone: '+43 664 7654321', hourly_rate_cents: 1500, active: true, created_at: iso('2026-06-03'), enrolment_code_expires_at: iso('2026-08-01T09:00:00Z'), enrolment_code_redeemed_at: null },
  { id: 4, name: 'Marta Süss', email: 'marta@example.at', phone: '+43 1 5350000', hourly_rate_cents: 1720, active: false, created_at: iso('2026-05-20'), enrolment_code_expires_at: null, enrolment_code_redeemed_at: null },
]

const CLIENTS = [
  { id: 1, name: 'HOIV Facility GmbH', active: true, created_at: iso('2026-06-01') },
  { id: 2, name: 'Arsenal Immobilien AG', active: true, created_at: iso('2026-06-01') },
  { id: 3, name: 'Ehemalig Hausverwaltung', active: false, created_at: iso('2026-01-01') },
]
const CONTACTS = [
  { id: 1, client_id: 1, name: 'Fr. Huber', email: 'huber@example.at', phone: '+43 1 3334444', active: true, created_at: iso('2026-06-01') },
  { id: 2, client_id: 2, name: 'Hr. Brenner', email: null, phone: null, active: true, created_at: iso('2026-06-01') },
  { id: 3, client_id: 1, name: 'Hr. Ausgeschieden', email: 'weg@example.at', phone: null, active: false, created_at: iso('2026-02-01') },
]

const loc = (over) => ({
  id: LOC_A, slug: 'hoiv', name: 'HOIV Arsenalstraße 11', address: 'Arsenalstraße 11, 1030 Wien',
  lat: null, lng: null, geocoded_at: iso('2026-08-11T23:37:47Z'), geocode_status: 'no_key',
  street_view_status: null, active: true, created_at: iso('2026-06-01'),
  client_id: 1, contact_id: 1, monthly_contract_cents: 120000, target_minutes_per_month: 2400,
  client_name: 'HOIV Facility GmbH', contact_name: 'Fr. Huber', ...over,
})

const LOCATIONS = [
  loc({}),
  loc({ id: LOC_B, slug: 'neuhaus', name: 'Neuhausgasse 4', address: 'Neuhausgasse 4, 1070 Wien', lat: 48.2011, lng: 16.3454, geocode_status: 'OK', street_view_status: 'REQUEST_DENIED', client_id: 2, contact_id: 2, client_name: 'Arsenal Immobilien AG', contact_name: 'Hr. Brenner', monthly_contract_cents: null, target_minutes_per_month: 1830 }),
  loc({ id: LOC_C, slug: 'lager', name: 'Lager Simmering', address: null, geocoded_at: null, geocode_status: null, active: false, client_id: null, contact_id: null, client_name: null, contact_name: null, monthly_contract_cents: 0, target_minutes_per_month: null }),
]

let shiftId = 1000
const shift = (over) => ({
  id: shiftId++, worker_id: 1, worker_name: 'Bálint Kovács', location_id: LOC_A,
  location_slug: 'hoiv', location_name: 'HOIV Arsenalstraße 11',
  start_time: iso('2026-07-14T06:00:00Z'), end_time: iso('2026-07-14T10:30:00Z'),
  auto_closed: false, corrected_at: null, client_uuid: 'aaaa-bbbb', created_at: iso('2026-07-14T06:00:00Z'), ...over,
})

/** Mixed-state July shifts: complete, open, unresolved(auto-closed), resolved, manual. */
function julyShifts() {
  shiftId = 1000
  return [
    shift({ start_time: iso('2026-08-12T04:10:00Z'), end_time: null, worker_id: 2, worker_name: 'Anna Nowak' }),
    shift({ start_time: iso('2026-08-11T20:00:00Z'), end_time: null, worker_id: 3, worker_name: 'Dragan Petrović', location_id: LOC_B, location_name: 'Neuhausgasse 4', location_slug: 'neuhaus' }),
    shift({ start_time: iso('2026-07-30T05:00:00Z'), end_time: iso('2026-07-30T13:00:00Z'), auto_closed: true, corrected_at: null }),
    shift({ start_time: iso('2026-07-29T05:00:00Z'), end_time: iso('2026-07-29T09:20:00Z'), auto_closed: true, corrected_at: iso('2026-07-31T10:00:00Z') }),
    shift({ start_time: iso('2026-07-28T06:00:00Z'), end_time: iso('2026-07-28T10:30:00Z'), client_uuid: null, worker_id: 2, worker_name: 'Anna Nowak' }),
    shift({ start_time: iso('2026-07-27T06:00:00Z'), end_time: iso('2026-07-27T09:45:00Z'), location_id: LOC_B, location_name: 'Neuhausgasse 4', location_slug: 'neuhaus' }),
    shift({ start_time: iso('2026-07-24T06:00:00Z'), end_time: iso('2026-07-24T11:15:00Z'), worker_id: 3, worker_name: 'Dragan Petrović' }),
    shift({ start_time: iso('2026-07-23T06:00:00Z'), end_time: iso('2026-07-23T10:00:00Z') }),
    shift({ start_time: iso('2026-07-22T06:00:00Z'), end_time: iso('2026-07-22T10:00:00Z'), worker_id: 2, worker_name: 'Anna Nowak' }),
    shift({ start_time: iso('2026-07-21T06:00:00Z'), end_time: iso('2026-07-21T10:00:00Z') }),
    shift({ start_time: iso('2026-07-20T06:00:00Z'), end_time: iso('2026-07-20T10:00:00Z'), location_id: LOC_B, location_name: 'Neuhausgasse 4', location_slug: 'neuhaus' }),
    shift({ start_time: iso('2026-07-17T06:00:00Z'), end_time: iso('2026-07-17T10:00:00Z') }),
  ]
}

/** 2000 rows = the server's SHIFT_PAGE_MAX. Triggers every truncation notice. */
function manyShifts(n = 2000) {
  shiftId = 5000
  const rows = []
  for (let i = 0; i < n; i++) {
    const day = new Date(Date.UTC(2026, 7, 11) - i * 3_600_000 * 6)
    rows.push(shift({
      start_time: day.toISOString(),
      end_time: new Date(day.getTime() + 4 * 3_600_000).toISOString(),
      worker_id: (i % 3) + 1,
      worker_name: WORKERS[i % 3].name,
    }))
  }
  return rows
}

const HOURS = [
  { worker_id: 1, hours: 32.5, pay_cents: 47125 },
  { worker_id: 2, hours: 18.25, pay_cents: 29200 },
  { worker_id: 3, hours: 22, pay_cents: 33000 },
]

function adminData(over = {}) {
  return {
    workers: WORKERS, locations: LOCATIONS, clients: CLIENTS, contacts: CONTACTS,
    shifts: julyShifts(), hours: HOURS,
    inventory: INVENTORY, material_requests: MATERIALS, material_request_limit: 500,
    portal_grants: GRANTS, settings: {},
    shift_limit: 2000,
    shift_range: { from: null, to: null },
    shift_bounds: { earliest: iso('2026-06-02T06:00:00Z'), latest: iso('2026-08-12T04:10:00Z') },
    ...over,
  }
}

const INVENTORY = [
  { id: 1, name: 'Allzweckreiniger 5 l', kind: 'product', unit_cost_cents: 1290, active: true, created_at: iso('2026-06-01') },
  { id: 2, name: 'Wischmopp Profi', kind: 'equipment', unit_cost_cents: 0, active: true, created_at: iso('2026-06-01') },
  { id: 3, name: 'Mikrofasertuch (10er)', kind: 'product', unit_cost_cents: 890, active: false, created_at: iso('2026-06-01') },
]

const MATERIALS = [
  { id: 1, worker_id: 1, worker_name: 'Bálint Kovács', location_id: LOC_A, location_name: 'HOIV Arsenalstraße 11', body: 'der blaue Reiniger, der große — wir haben keinen mehr', status: 'submitted', admin_note: null, inventory_item_id: null, item_name: null, quantity: null, cost_cents: null, decided_by: null, decided_at: null, ordered_at: null, arrived_at: null, seen_at: null, created_at: iso('2026-08-11T14:00:00Z') },
  { id: 2, worker_id: 2, worker_name: 'Anna Nowak', location_id: null, location_name: null, body: 'Wischmopp kaputt', status: 'approved', admin_note: 'beim Großhändler bestellen', inventory_item_id: 2, item_name: 'Wischmopp Profi', quantity: 2, cost_cents: null, decided_by: 1, decided_at: iso('2026-08-10T09:00:00Z'), ordered_at: null, arrived_at: null, seen_at: null, created_at: iso('2026-08-09T11:00:00Z') },
  { id: 3, worker_id: 3, worker_name: 'Dragan Petrović', location_id: LOC_B, location_name: 'Neuhausgasse 4', body: 'Handschuhe Größe L', status: 'ordered', admin_note: null, inventory_item_id: null, item_name: null, quantity: null, cost_cents: null, decided_by: 1, decided_at: iso('2026-07-20T09:00:00Z'), ordered_at: iso('2026-07-21T09:00:00Z'), arrived_at: null, seen_at: null, created_at: iso('2026-07-19T09:00:00Z') },
  { id: 4, worker_id: 1, worker_name: 'Bálint Kovács', location_id: LOC_A, location_name: 'HOIV Arsenalstraße 11', body: 'Allzweckreiniger nachbestellen', status: 'arrived', admin_note: null, inventory_item_id: 1, item_name: 'Allzweckreiniger 5 l', quantity: 4, cost_cents: 5160, decided_by: 1, decided_at: iso('2026-07-05T09:00:00Z'), ordered_at: iso('2026-07-06T09:00:00Z'), arrived_at: iso('2026-07-09T09:00:00Z'), seen_at: iso('2026-07-09T15:00:00Z'), created_at: iso('2026-07-04T09:00:00Z') },
  { id: 5, worker_id: 2, worker_name: 'Anna Nowak', location_id: null, location_name: null, body: 'neue Leiter', status: 'rejected', admin_note: 'zu teuer, im September', inventory_item_id: null, item_name: null, quantity: null, cost_cents: null, decided_by: 1, decided_at: iso('2026-07-02T09:00:00Z'), ordered_at: null, arrived_at: null, seen_at: null, created_at: iso('2026-07-01T09:00:00Z') },
]

const GRANTS = [
  { token_hash: 'deadbeef'.repeat(8), contact_id: 1, location_id: LOC_A, created_at: iso('2026-07-01T09:00:00Z'), contact_name: 'Fr. Huber', location_name: 'HOIV Arsenalstraße 11' },
]

const plBuilding = (over) => ({
  location_id: LOC_A, slug: 'hoiv', name: 'HOIV Arsenalstraße 11', active: true,
  client_id: 1, client_name: 'HOIV Facility GmbH',
  labour_seconds: 117000, labour_minutes: 1950, labour_cents: 47125, material_cents: 3870,
  revenue_cents: 120000, revenue_unknown_reason: null, revenue_days: 31, period_days: 31,
  target_minutes: 2400, target_unknown_days: 0,
  profit_cents: 69005, margin_bp: 5750, margin_unknown_reason: null, below_baseline: false,
  excluded_unresolved_shifts: 0, excluded_unresolved_seconds: 0, open_shifts: 0, ...over,
})

const PL_REPORT = {
  range: { from: iso('2026-06-30T22:00:00Z'), to: iso('2026-07-31T22:00:00Z') },
  period_days: 31, timezone: 'Europe/Vienna',
  baseline_margin_bp: 3000, baseline_set: true,
  labour: { rate_basis: 'current', rate_basis_note: 'Arbeitskosten zu aktuellen Stundensätzen.' },
  materials: { basis: 'pro_rata_labour_hours', basis_decision: 'decision-6', pool_cents: 5160, allocated_cents: 5160, unallocated_cents: 0, unallocated_reason: null, unpriced_requests: 2, priced_requests: 1 },
  buildings: [
    plBuilding({}),
    plBuilding({ location_id: LOC_B, slug: 'neuhaus', name: 'Neuhausgasse 4', client_id: 2, client_name: 'Arsenal Immobilien AG', labour_cents: 62000, labour_minutes: 2480, material_cents: 1290, revenue_cents: 68000, revenue_days: 20, profit_cents: 4710, margin_bp: 692, below_baseline: true, excluded_unresolved_shifts: 2, excluded_unresolved_seconds: 28800, open_shifts: 1 }),
    plBuilding({ location_id: LOC_C, slug: 'lager', name: 'Lager Simmering', active: false, client_id: null, client_name: null, labour_cents: 12000, labour_minutes: 480, material_cents: 0, revenue_cents: null, revenue_unknown_reason: 'no_contract', revenue_days: 0, target_minutes: null, target_unknown_days: 31, profit_cents: null, margin_bp: null, margin_unknown_reason: 'no_contract', below_baseline: null }),
  ],
}

const trend = (base) => Array.from({ length: 6 }, (_, i) => ({
  month: `2026-0${i + 2}`, actual_minutes: Math.round(base * (0.7 + i * 0.09)), shifts: 4 + i,
}))

const ANALYTICS = {
  range: PL_REPORT.range, period_days: 31, timezone: 'Europe/Vienna', trend_months: 6,
  buildings: [
    { location_id: LOC_A, slug: 'hoiv', name: 'HOIV Arsenalstraße 11', active: true, address: 'Arsenalstraße 11, 1030 Wien', client_id: 1, client_name: 'HOIV Facility GmbH', contact_id: 1, contact_name: 'Fr. Huber', lat: null, lng: null, geocoded_at: iso('2026-08-11T23:37:47Z'), geocode_state: 'failed', geocode_status: 'no_key', street_view_status: null, actual_minutes: 1950, target_minutes: 2400, target_unknown_days: 0, variance_minutes: -450, trend: trend(1950), trend_delta_minutes: 175, trend_direction: 'up', trend_reason: null, excluded_unresolved_shifts: 0, excluded_unresolved_seconds: 0, open_shifts: 0 },
    { location_id: LOC_B, slug: 'neuhaus', name: 'Neuhausgasse 4', active: true, address: 'Neuhausgasse 4, 1070 Wien', client_id: 2, client_name: 'Arsenal Immobilien AG', contact_id: 2, contact_name: 'Hr. Brenner', lat: 48.2011, lng: 16.3454, geocoded_at: iso('2026-07-02T09:00:00Z'), geocode_state: 'pinned', geocode_status: 'OK', street_view_status: 'REQUEST_DENIED', actual_minutes: 2480, target_minutes: 1830, target_unknown_days: 0, variance_minutes: 650, trend: trend(2480), trend_delta_minutes: -220, trend_direction: 'down', trend_reason: null, excluded_unresolved_shifts: 2, excluded_unresolved_seconds: 28800, open_shifts: 1 },
    { location_id: LOC_C, slug: 'lager', name: 'Lager Simmering', active: false, address: null, client_id: null, client_name: null, contact_id: null, contact_name: null, lat: null, lng: null, geocoded_at: null, geocode_state: 'never_attempted', geocode_status: null, street_view_status: null, actual_minutes: 480, target_minutes: null, target_unknown_days: 31, variance_minutes: null, trend: trend(0), trend_delta_minutes: null, trend_direction: null, trend_reason: 'insufficient_data', excluded_unresolved_shifts: 0, excluded_unresolved_seconds: 0, open_shifts: 0 },
  ],
}

const CONTRACT_HISTORY = [
  { id: 3, location_id: LOC_A, client_id: 1, monthly_contract_cents: 120000, target_minutes_per_month: 2400, valid_from: '2026-07-01', valid_to: null, note: 'Indexanpassung 2026', created_at: iso('2026-06-28') },
  { id: 2, location_id: LOC_A, client_id: 1, monthly_contract_cents: 110000, target_minutes_per_month: 2400, valid_from: '2026-01-01', valid_to: '2026-07-01', note: null, created_at: iso('2025-12-20') },
  { id: 1, location_id: LOC_A, client_id: 3, monthly_contract_cents: 98000, target_minutes_per_month: null, valid_from: '2025-03-01', valid_to: '2026-01-01', note: 'Altvertrag', created_at: iso('2025-02-20') },
]

const PORTAL = {
  building: { name: 'HOIV Arsenalstraße 11' },
  cleanings: [
    { date: '2026-07-30', first_name: 'Bálint', minutes: 270 },
    { date: '2026-07-28', first_name: 'Anna', minutes: 270 },
    { date: '2026-07-24', first_name: 'Dragan', minutes: 315 },
  ],
}

// --- the stub ------------------------------------------------------------------------
/** Mutated by the driver before each navigation. Never talks to production. */
let scenario = { data: adminData(), pl: PL_REPORT, analytics: ANALYTICS, contracts: CONTRACT_HISTORY, portal: PORTAL, status: 200, delayMs: 0 }

const json = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json' })
  res.end(JSON.stringify(body))
}

const srv = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x')
  const p = u.pathname

  if (p.startsWith('/admin/') || p.startsWith('/portal/')) {
    if (scenario.delayMs > 0) await sleep(scenario.delayMs)
    if (scenario.status !== 200) return json(res, scenario.status, { error: 'stub' })
    if (p === '/admin/data') return json(res, 200, scenario.data)
    if (p === '/admin/pl') return json(res, 200, scenario.pl)
    if (p === '/admin/analytics') return json(res, 200, scenario.analytics)
    if (/^\/admin\/locations\/[^/]+\/contracts$/.test(p)) return json(res, 200, { contracts: scenario.contracts })
    if (p.startsWith('/portal/')) return json(res, 200, scenario.portal)
    if (p === '/admin/login') return json(res, 401, { error: 'invalid' })
    return json(res, 200, {})
  }

  let f = path.join(OUT, p === '/' ? 'index.html' : p)
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html')
  if (!fs.existsSync(f) && fs.existsSync(`${f}.html`)) f += '.html'
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end('nope') }
  const ext = path.extname(f)
  res.writeHead(200, { 'content-type': ext === '.js' ? 'text/javascript' : ext === '.css' ? 'text/css' : ext === '.woff2' ? 'font/woff2' : 'text/html' })
  res.end(fs.readFileSync(f))
})
await new Promise((r) => srv.listen(8099, '127.0.0.1', r))

// --- scenarios ------------------------------------------------------------------------
const S = (name, url, patch = {}, act = null) => ({ name, url, patch, act })

const empty = { workers: [], locations: [], clients: [], contacts: [], shifts: [], hours: [], inventory: [], material_requests: [], portal_grants: [], shift_bounds: { earliest: null, latest: null } }
/** Shifts exist, but all older than the 30-day default window: the "empty filter" trap. */
const oldOnly = {
  shifts: [shift({ start_time: iso('2026-05-04T06:00:00Z'), end_time: iso('2026-05-04T10:00:00Z') }), shift({ start_time: iso('2026-05-02T06:00:00Z'), end_time: iso('2026-05-02T10:00:00Z') })],
  shift_bounds: { earliest: iso('2026-05-02T06:00:00Z'), latest: iso('2026-05-04T06:00:00Z') },
  hours: [],
}

const SCENARIOS = [
  S('dashboard-loading', '/', { delayMs: 20000 }),
  S('dashboard-empty', '/', { data: adminData(empty) }),
  S('dashboard-populated', '/', {}),
  S('dashboard-error-500', '/', { status: 500 }),
  S('dashboard-401-redirect', '/', { status: 401 }),
  S('dashboard-overlimit', '/', { data: adminData({ shifts: manyShifts() }) }),

  S('shifts-loading', '/shifts/', { delayMs: 20000 }),
  S('shifts-empty-database', '/shifts/', { data: adminData(empty) }),
  S('shifts-empty-filtered', '/shifts/', { data: adminData(oldOnly) }),
  S('shifts-populated', '/shifts/', {}),
  S('shifts-overlimit', '/shifts/', { data: adminData({ shifts: manyShifts() }) }),
  S('shifts-error-500', '/shifts/', { status: 500 }),
  S('shifts-correction-form', '/shifts/', {}, async (page) => {
    await page.clickText('Korrigieren'); await sleep(600)
  }),

  // Deep links, the whole point of the URL contract. `worker=999` is well formed and
  // matches nothing: it must show EVERY row plus a banner, never an empty table (G4).
  S('shifts-link-worker', '/shifts/?worker=2&period=all', {}),
  S('shifts-link-unknown-worker', '/shifts/?worker=999&period=all', {}),
  S('shifts-link-absolute-range', '/shifts/?worker=1&from=2026-06-30T22:00:00.000Z&to=2026-07-31T22:00:00.000Z', {}),
  S('shifts-link-malformed', '/shifts/?worker=abc&state=purple', {}),
  S('shifts-link-state-unresolved', '/shifts/?state=unresolved&period=all', {}),
  S('shifts-create-open', '/shifts/', {}, async (page) => {
    await page.clickText('Schicht von Hand erfassen'); await sleep(600)
  }),

  S('workers-empty', '/workers/', { data: adminData(empty) }),
  S('workers-populated', '/workers/', {}),
  S('workers-error-500', '/workers/', { status: 500 }),

  S('locations-empty', '/locations/', { data: adminData(empty) }),
  S('locations-populated', '/locations/', {}),
  S('locations-month-empty', '/locations/', { data: adminData(oldOnly) }),
  S('locations-overlimit', '/locations/', { data: adminData({ shifts: manyShifts() }) }),

  S('clients-empty', '/clients/', { data: adminData(empty) }),
  S('clients-populated', '/clients/', {}),

  S('inventory-empty', '/inventory/', { data: adminData(empty) }),
  S('inventory-populated', '/inventory/', {}),

  S('materials-empty-queue', '/material-requests/', { data: adminData({ material_requests: MATERIALS.filter((m) => ['arrived', 'rejected'].includes(m.status)) }) }),
  S('materials-populated', '/material-requests/', {}),
  S('materials-detail-form', '/material-requests/', {}, async (page) => {
    await page.clickText('Details'); await sleep(600)
  }),

  S('contracts-no-buildings', '/contracts/', { data: adminData(empty) }),
  S('contracts-populated', '/contracts/', {}),
  S('contracts-history-open', '/contracts/', {}, async (page) => {
    await page.clickText('Verlauf'); await sleep(900)
  }),

  S('payroll-loading', '/payroll/', { delayMs: 20000 }),
  S('payroll-empty-period', '/payroll/', { data: adminData(oldOnly) }),
  S('payroll-populated', '/payroll/', {}),
  S('payroll-overlimit-reconcile', '/payroll/', { data: adminData({ shifts: manyShifts() }) }),
  S('payroll-error-500', '/payroll/', { status: 500 }),

  S('pl-populated-flagged', '/pl/', {}),
  S('pl-no-baseline', '/pl/', { pl: { ...PL_REPORT, baseline_margin_bp: null, baseline_set: false, buildings: PL_REPORT.buildings.map((b) => ({ ...b, below_baseline: null, margin_unknown_reason: b.margin_unknown_reason })) } }),
  S('pl-empty', '/pl/', { pl: { ...PL_REPORT, buildings: [] } }),
  S('pl-error-500', '/pl/', { status: 500 }),

  S('analytics-map-nokey', '/analytics/', {}),
  S('analytics-detail-panel', '/analytics/', {}, async (page) => {
    await page.clickText('Details'); await sleep(900)
  }),
  S('analytics-empty', '/analytics/', { analytics: { ...ANALYTICS, buildings: [] } }),

  // English is kept in the switcher (decision-8): key parity is mechanical, LAYOUT is not.
  // Every English string is shorter than its German original, so this is the cheap check
  // that nothing was sized to German by accident.
  S('shifts-english', '/shifts/', {}, async (page) => {
    await page.eval(`window.localStorage.setItem('nfcts.locale', 'en'); location.reload()`)
    await sleep(1600)
  }),
  S('payroll-english', '/payroll/', {}, async (page) => {
    await page.eval(`window.localStorage.setItem('nfcts.locale', 'en'); location.reload()`)
    await sleep(1600)
  }),

  S('login-idle', '/login/', {}),
  S('login-failed', '/login/', {}, async (page) => {
    await page.type('input[type=email]', 'chef@example.at', { perChar: 5 })
    await page.type('input[type=password]', 'falsch', { perChar: 5 })
    await page.clickText('Anmelden'); await sleep(800)
  }),

  S('portal-populated', '/reinigung/#k=' + 'A'.repeat(43), {}),
  S('portal-empty', '/reinigung/#k=' + 'A'.repeat(43), { portal: { building: { name: 'HOIV Arsenalstraße 11' }, cleanings: [] } }),
  S('portal-invalid-link', '/reinigung/#k=' + 'A'.repeat(43), { status: 404 }),
  S('portal-no-token', '/reinigung/', {}),
]

// --- drive ----------------------------------------------------------------------------
const ALL_WIDTHS = [
  { w: 390, h: 844, mobile: true, tag: '390' },
  { w: 1280, h: 900, mobile: false, tag: '1280' },
]
const WIDTHS = process.env.ONLY_W ? ALL_WIDTHS.filter((v) => v.tag === process.env.ONLY_W) : ALL_WIDTHS
const MAX_SHOT_HEIGHT = 4200

const only = process.argv[2] ? new RegExp(process.argv[2]) : null
const list = only ? SCENARIOS.filter((s) => only.test(s.name)) : SCENARIOS

const chrome = await launchChrome({ port: 9346, width: 1280, height: 900 })
const page = await attach(9346)
const findings = []

for (const view of WIDTHS) {
  for (const sc of list) {
    scenario = { data: adminData(), pl: PL_REPORT, analytics: ANALYTICS, contracts: CONTRACT_HISTORY, portal: PORTAL, status: 200, delayMs: 0, ...sc.patch }
    await page.send('Emulation.setDeviceMetricsOverride', { width: view.w, height: view.h, deviceScaleFactor: 1, mobile: view.mobile })
    // A pure hash change is a same-document navigation and never fires load: park on
    // about:blank first so every scenario is a real document load.
    await page.goto('about:blank', { settle: 60 })
    await page.goto(`http://127.0.0.1:8099${sc.url}`, { settle: sc.patch.delayMs ? 1200 : 1400 })
    if (sc.act) { try { await sc.act(page) } catch (e) { console.log(`   ! act failed ${sc.name}: ${String(e).slice(0, 120)}`) } }
    await sleep(300)

    const metrics = JSON.parse(await page.eval(`JSON.stringify({
      h: Math.min(${MAX_SHOT_HEIGHT}, document.documentElement.scrollHeight),
      sideways: document.documentElement.scrollWidth > window.innerWidth + 1,
      labelled: document.querySelectorAll('td[data-label]').length,
      tds: document.querySelectorAll('table.data-table tbody td').length,
      tiny: [...document.querySelectorAll('button,a.nav-link,select,input')].filter(e=>{const b=e.getBoundingClientRect();return b.height>0&&b.height<44}).length,
      path: location.pathname,
      text: document.body.innerText.slice(0, 400)
    })`))

    await page.send('Emulation.setDeviceMetricsOverride', { width: view.w, height: metrics.h, deviceScaleFactor: 1, mobile: view.mobile })
    await sleep(250)
    const file = path.join(SHOTS, `${sc.name}-${view.tag}.png`)
    await page.screenshot(file)
    findings.push({ name: sc.name, view: view.tag, ...metrics })
    console.log(`${sc.name.padEnd(28)} ${view.tag.padStart(4)}  h=${String(metrics.h).padStart(4)} sideways=${metrics.sideways} labelled=${metrics.labelled}/${metrics.tds} sub44=${metrics.tiny} path=${metrics.path}`)
  }
}

fs.writeFileSync(`/tmp/states-metrics-${process.env.ONLY_W ?? 'all'}-${Date.now()}.json`, JSON.stringify(findings, null, 2))
await page.close()
try { chrome.child?.kill?.() } catch {}
srv.close()
process.exit(0)
