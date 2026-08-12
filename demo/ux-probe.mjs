// Layout regressions that only a real layout engine can see, measured against the built
// bundle in `web/out` with the same stubbed API the state capture uses.
//
// Every check here exists because an ASSERTION about the DOM passed while the PICTURE was
// wrong. `data-label` counts were 791/791 correct while the labels were off by one column;
// the shift table's headers rendered vertically while every selector still matched. So
// these measure PIXELS, and each one names the edit that makes it go RED.
//
//   node demo/ux-probe.mjs
//   node demo/ux-probe.mjs --mutate overflow-anywhere    (proves the check can fail)
//
// No new dependency: demo/cdp.mjs drives headless Chrome (decision-16).
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { attach, launchChrome, sleep } from './cdp.mjs'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const OUT = path.join(ROOT, 'web/out')
const PORT = 8098

/** The stub. Shape copied from demo/ux-states.mjs; only what these probes read. */
const LOC_A = 'c3c37d4a-ca0a-42c5-b248-9704b9907ec7'
const iso = (s) => new Date(s).toISOString()

// The SAME rows the UX audit measured 275px of text columns on. The fixture matters: the
// column crush only appears when a row carries a long address, a long enrolment sentence
// and a long German status together, which is exactly a real crew.
const WORKERS = [
  { id: 1, name: 'Bálint Kovács', email: 'balint.kovacs@hoiv-facility.example.at', phone: '+43 660 1234567', hourly_rate_cents: 1450, active: true, created_at: iso('2026-06-01'), enrolment_code_expires_at: iso('2026-08-12T09:00:00Z'), enrolment_code_redeemed_at: null },
  { id: 2, name: 'Anna Nowak', email: 'anna.nowak@hoiv-facility.example.at', phone: null, hourly_rate_cents: 1600, active: true, created_at: iso('2026-06-02'), enrolment_code_expires_at: null, enrolment_code_redeemed_at: iso('2026-07-14T08:12:00Z') },
  { id: 3, name: 'Dragan Petrović', email: null, phone: '+43 664 7654321', hourly_rate_cents: 1500, active: true, created_at: iso('2026-06-03'), enrolment_code_expires_at: iso('2026-08-01T09:00:00Z'), enrolment_code_redeemed_at: null },
  { id: 4, name: 'Marta Süss', email: 'marta.suess@hoiv-facility.example.at', phone: '+43 1 5350000', hourly_rate_cents: 1720, active: false, created_at: iso('2026-05-20'), enrolment_code_expires_at: null, enrolment_code_redeemed_at: null },
]
const LOCATIONS = [
  { id: LOC_A, slug: 'hoiv', name: 'HOIV Arsenalstraße 11', address: 'Arsenalstraße 11, 1030 Wien', lat: null, lng: null, geocoded_at: null, geocode_status: null, street_view_status: null, active: true, created_at: iso('2026-06-01'), client_id: null, contact_id: null, monthly_contract_cents: 120000, target_minutes_per_month: 2400, client_name: null, contact_name: null },
]
const SHIFTS = [
  { id: 1, worker_id: 1, worker_name: 'Bálint Kovács', location_id: LOC_A, location_slug: 'hoiv', location_name: 'HOIV Arsenalstraße 11', start_time: iso('2026-08-10T06:00:00Z'), end_time: iso('2026-08-10T10:30:00Z'), auto_closed: false, corrected_at: null, client_uuid: 'a', created_at: iso('2026-08-10T06:00:00Z') },
  { id: 2, worker_id: 2, worker_name: 'Anna Nowak', location_id: LOC_A, location_slug: 'hoiv', location_name: 'HOIV Arsenalstraße 11', start_time: iso('2026-08-09T06:00:00Z'), end_time: iso('2026-08-09T10:30:00Z'), auto_closed: false, corrected_at: null, client_uuid: 'b', created_at: iso('2026-08-09T06:00:00Z') },
]
const DATA = {
  workers: WORKERS, locations: LOCATIONS, clients: [], contacts: [],
  shifts: SHIFTS, hours: [{ worker_id: 1, hours: 4.5, pay_cents: 6525 }, { worker_id: 2, hours: 4.5, pay_cents: 7200 }],
  inventory: [], material_requests: [], material_request_limit: 500, portal_grants: [], settings: {},
  shift_limit: 2000, shift_range: { from: null, to: null },
  shift_bounds: { earliest: iso('2026-08-09T06:00:00Z'), latest: iso('2026-08-10T06:00:00Z') },
}
const plBuilding = {
  location_id: LOC_A, slug: 'hoiv', name: 'HOIV Arsenalstraße 11', active: true, client_id: null, client_name: null,
  labour_seconds: 117000, labour_minutes: 1950, labour_cents: 47125, material_cents: 3870,
  revenue_cents: 120000, revenue_unknown_reason: null, revenue_days: 31, period_days: 31,
  target_minutes: 2400, target_unknown_days: 0, profit_cents: 69005, margin_bp: 5750,
  margin_unknown_reason: null, below_baseline: false,
  excluded_unresolved_shifts: 0, excluded_unresolved_seconds: 0, open_shifts: 0,
}
// THREE buildings with real German names and a client column, because /pl/ is the widest
// table in the panel and a one-row fixture cannot reproduce its width. A benign fixture is
// how a `sideways=true` regression got past this probe once already.
const PL = {
  range: { from: iso('2026-06-30T22:00:00Z'), to: iso('2026-07-31T22:00:00Z') },
  period_days: 31, timezone: 'Europe/Vienna', baseline_margin_bp: 3000, baseline_set: true,
  labour: { rate_basis: 'current', rate_basis_note: 'x' },
  materials: { basis: 'pro_rata_labour_hours', basis_decision: 'decision-6', pool_cents: 3870, allocated_cents: 3870, unallocated_cents: 0, unallocated_reason: null, unpriced_requests: 2, priced_requests: 1 },
  buildings: [
    { ...plBuilding, client_name: 'HOIV Facility GmbH', client_id: 1 },
    { ...plBuilding, location_id: '1a2b3c4d-0000-4000-8000-000000000002', slug: 'neuhaus', name: 'Neuhausgasse 4', client_id: 2, client_name: 'Arsenal Immobilien AG', labour_cents: 62000, labour_minutes: 2480, material_cents: 1290, revenue_cents: 68000, revenue_days: 20, profit_cents: 4710, margin_bp: 692, below_baseline: true, excluded_unresolved_shifts: 2, excluded_unresolved_seconds: 28800, open_shifts: 1 },
    { ...plBuilding, location_id: '1a2b3c4d-0000-4000-8000-000000000003', slug: 'lager', name: 'Lager Simmering', active: false, client_id: null, client_name: null, labour_cents: 12000, labour_minutes: 480, material_cents: 0, revenue_cents: null, revenue_unknown_reason: 'no_contract', revenue_days: 0, target_minutes: null, target_unknown_days: 31, profit_cents: null, margin_bp: null, margin_unknown_reason: 'no_contract', below_baseline: null },
  ],
}

/**
 * `--mutate <name>` rewrites the SERVED stylesheet on the fly, so a probe can be proven
 * able to fail without editing the repo. A check whose negative case cannot fail is not a
 * check, and this repo has shipped three of those.
 */
const MUTATIONS = {
  // THE AUDIT BASELINE: the three table rules exactly as they shipped, restored into the
  // built (minified) stylesheet. This is the mutation that matters, because it is not a
  // hypothetical edit — it is the code that produced `workers-populated-1280.png`.
  //   1. `overflow-wrap: anywhere` on the cell (UX-AUDIT finding 3)
  //   2. no hyphenation, because there was none
  //   3. no floor under the row header, because there was none
  'audit-baseline': (css) =>
    css
      .replace(
        '.data-table th,.data-table td{padding:var(--row-y)var(--space-3);text-align:left;vertical-align:top;border-bottom:1px solid var(--border);line-height:var(--leading-dense);overflow-wrap:break-word;-webkit-hyphens:auto;hyphens:auto}',
        '.data-table th,.data-table td{padding:var(--space-2)var(--space-3);text-align:left;vertical-align:top;border-bottom:1px solid var(--border);overflow-wrap:anywhere}',
      )
      .replace(
        '.data-table tbody th,.data-table tfoot th{-webkit-hyphens:manual;hyphens:manual;min-width:var(--col-name)}',
        '.data-table tbody th,.data-table tfoot th{}',
      )
      //   4. `.cell-actions { white-space: nowrap }`, which makes the two action cells
      //      incompressible so they take the width the text columns needed.
      .replace('.cell-actions{white-space:normal}', '.cell-actions{white-space:nowrap}')
      //   6. `.col-numeric` back to its (0,1,0) form, which the cascade discards.
      .replace('.data-table th.col-numeric,.data-table td.col-numeric,.col-numeric{', '.col-numeric{')
      //   5. buttons breaking mid-word, which they did because they inherited `anywhere`.
      .replace(';-webkit-hyphens:manual;hyphens:manual;overflow-wrap:normal;cursor:pointer', ';cursor:pointer'),
  // MEASURED, and worth recording: NO SINGLE ingredient above is sufficient on its own.
  // `overflow-wrap: anywhere` alone leaves the four text columns at 754px; removing only
  // the row-header floor leaves them wide too. The crush needs `anywhere` AND the
  // incompressible nowrap action cells AND no floor under the name, together — which is
  // why it survived every rule-by-rule reading of the stylesheet and was only ever caught
  // by looking at a picture. `overflow-wrap: anywhere` on its own is still forbidden, and
  // web/scripts/check-design-tokens.mjs is what forbids it (mutation-proven there).
}
const mutation = process.argv.includes('--mutate')
  ? process.argv[process.argv.indexOf('--mutate') + 1]
  : null
if (mutation !== null && MUTATIONS[mutation] === undefined) {
  process.stderr.write(`unknown mutation "${mutation}"; have: ${Object.keys(MUTATIONS)}\n`)
  process.exit(2)
}
let mutationApplied = false

const json = (res, body) => {
  res.writeHead(200, { 'content-type': 'application/json' })
  res.end(JSON.stringify(body))
}

const srv = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x')
  const p = u.pathname
  if (p.startsWith('/admin/') || p.startsWith('/portal/')) {
    if (p === '/admin/data') return json(res, DATA)
    if (p === '/admin/pl') return json(res, PL)
    return json(res, {})
  }
  let f = path.join(OUT, p === '/' ? 'index.html' : p)
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html')
  if (!fs.existsSync(f) && fs.existsSync(`${f}.html`)) f += '.html'
  if (!fs.existsSync(f)) {
    res.writeHead(404)
    return res.end('nope')
  }
  const ext = path.extname(f)
  let body = fs.readFileSync(f)
  if (ext === '.css' && mutation !== null) {
    const before = body.toString('utf8')
    const after = MUTATIONS[mutation](before)
    // A mutation that changes nothing produces a GREEN run that proves the opposite of what
    // it claims. Refuse loudly instead — this exact trap (a regex written against the
    // unminified source) already produced one false all-clear here.
    if (after !== before) mutationApplied = true
    body = Buffer.from(after)
  }
  res.writeHead(200, {
    'content-type':
      ext === '.js' ? 'text/javascript' : ext === '.css' ? 'text/css' : 'text/html',
  })
  res.end(body)
})
await new Promise((r) => srv.listen(PORT, '127.0.0.1', r))

const chrome = await launchChrome({ port: 9347, width: 1280, height: 900 })
const page = await attach(9347)

const results = []
const record = (name, ok, detail) => {
  results.push({ name, ok, detail })
  process.stdout.write(`  ${ok ? 'ok  ' : 'FAIL'} ${name}\n         ${detail}\n`)
}

async function visit(url, width, height) {
  await page.send('Emulation.setDeviceMetricsOverride', {
    width, height, deviceScaleFactor: 1, mobile: width < 768,
  })
  await page.goto('about:blank', { settle: 60 })
  await page.goto(`http://127.0.0.1:${PORT}${url}`, { settle: 1400 })
  await sleep(250)
}

const evalJson = async (expression) => JSON.parse(await page.eval(expression))

// --- A. the column crush (UX-AUDIT finding 3) -------------------------------------------
//
// `overflow-wrap: anywhere` on a table cell contributes to min-content width, so one
// incompressible cell steals the table and every text column collapses. RED before the
// fix by construction; `--mutate overflow-anywhere` puts it back to prove it.
await visit('/workers/', 1280, 900)
const cols = await evalJson(`JSON.stringify((() => {
  const table = document.querySelector('table.data-table')
  if (!table) return { error: 'no table' }
  const ths = [...table.querySelectorAll('thead th')]
  return {
    widths: ths.map(th => Math.round(th.getBoundingClientRect().width)),
    labels: ths.map(th => th.textContent.trim()),
    tableWidth: Math.round(table.getBoundingClientRect().width),
  }
})())`)
// The four columns a director actually READS on /workers/: name, email, phone, status.
// (Rate is numeric; the enrolment-code column is the INCOMPRESSIBLE one and is excluded on
// purpose — under the audit baseline it swells to 477px by taking exactly what these four
// lost, so including it hides the defect inside its own cause.)
const TEXT_COLUMNS = [0, 1, 2, 4]
const MIN_READABLE = 80 // px: about 9 characters at 16px. Below this a column is a stripe.
const narrow = TEXT_COLUMNS.filter((i) => (cols.widths[i] ?? 0) < MIN_READABLE)
const textWidth = TEXT_COLUMNS.reduce((sum, i) => sum + (cols.widths[i] ?? 0), 0)
record(
  `workers: no text column is crushed below ${MIN_READABLE}px`,
  narrow.length === 0,
  `${textWidth}px across four columns — ${cols.labels.map((l, i) => `${l}:${cols.widths[i]}`).join(' ')}`,
)

// --- B. no sideways scroll, at either width ---------------------------------------------
//
// A page that scrolls sideways is the failure decision-7 predicted and decision-29 took on.
// Checked on the money screens, where reserved numeric column widths could reintroduce it.
for (const [url, width] of [
  ['/pl/', 1280], ['/pl/', 390],
  ['/payroll/', 1280], ['/payroll/', 390],
  ['/shifts/', 1280], ['/shifts/', 390],
  ['/workers/', 1280], ['/workers/', 390],
  ['/locations/', 1280], ['/locations/', 390],
]) {
  await visit(url, width, width < 768 ? 844 : 900)
  const m = await evalJson(`JSON.stringify({
    scrollW: document.documentElement.scrollWidth,
    innerW: window.innerWidth,
  })`)
  record(
    `${url} at ${width}px does not scroll sideways`,
    m.scrollW <= m.innerW + 1,
    `scrollWidth ${m.scrollW} vs innerWidth ${m.innerW}`,
  )
}

// --- B2. money is actually right-aligned -----------------------------------------------
//
// COMPUTED style, not the class name. `.col-numeric` is (0,1,0) and loses to
// `.data-table td` at (0,2,0), so for the whole life of the class every money column was
// left-aligned while every assertion about `className` passed. A column of amounts that
// does not line up on the decimal cannot be totalled by eye, which is the one thing a
// payroll column is for.
await visit('/payroll/', 1280, 900)
const aligned = await evalJson(`JSON.stringify([...document.querySelectorAll('.data-table td.col-numeric, .data-table th.col-numeric')].map(c => getComputedStyle(c).textAlign))`)
record(
  'payroll: every .col-numeric cell computes to text-align: right',
  aligned.length > 0 && aligned.every((a) => a === 'right'),
  `${aligned.length} cells: ${[...new Set(aligned)].join(', ')}`,
)

// --- C. the totals row is labelled on a phone (UX-AUDIT finding 7) ----------------------
//
// Four unlabelled numbers is the row a director reads down the phone before paying people.
// RED if the `tfoot` loop is removed from components/ResponsiveTableLabels.tsx.
await visit('/payroll/', 390, 844)
const foot = await evalJson(`JSON.stringify((() => {
  const cells = [...document.querySelectorAll('table.data-table tfoot td')]
  return {
    total: cells.length,
    labelled: cells.filter(c => c.hasAttribute('data-label')).length,
    withValue: cells.filter(c => c.textContent.trim() !== '').length,
    labels: cells.map(c => c.getAttribute('data-label')),
  }
})())`)
record(
  'payroll totals row: every non-empty tfoot cell prints its column heading at 390px',
  foot.withValue > 0 && foot.labelled === foot.withValue,
  `${foot.labelled} labelled of ${foot.withValue} non-empty (${foot.total} cells): ${JSON.stringify(foot.labels)}`,
)

// --- D. G4: an unknown filter shows EVERYTHING, never an empty table ---------------------
//
// The single most dangerous rule in the URL contract. `?worker=999` is well-formed and
// matches nothing; an empty table here is indistinguishable from data loss.
await visit('/shifts/?worker=999&period=all', 1280, 900)
const g4 = await evalJson(`JSON.stringify({
  rows: document.querySelectorAll('table.data-table tbody tr').length,
  banner: [...document.querySelectorAll('.notice')].map(n => n.textContent.trim()).join(' | '),
})`)
record(
  'shifts ?worker=999 (unknown id) shows ALL rows plus a banner naming the value',
  g4.rows === SHIFTS.length && g4.banner.includes('999') && /fehlt nichts|nothing is missing/i.test(g4.banner),
  `${g4.rows} rows (expected ${SHIFTS.length}); banner: ${g4.banner.slice(0, 160)}`,
)

// --- E. a valid filter actually filters, and says that it did ---------------------------
await visit('/shifts/?worker=2&period=all', 1280, 900)
const filtered = await evalJson(`JSON.stringify({
  rows: [...document.querySelectorAll('table.data-table tbody tr th')].map(t => t.textContent.trim()),
  chip: document.querySelector('.filter-chip')?.textContent.trim() ?? '',
})`)
record(
  'shifts ?worker=2 filters to that person AND renders a removable chip saying so',
  filtered.rows.length === 1 && filtered.rows[0].includes('Anna') && filtered.chip.includes('Anna'),
  `rows ${JSON.stringify(filtered.rows)}; chip "${filtered.chip.slice(0, 120)}"`,
)

// --- F. an error state does not also claim to be loading (UX-AUDIT finding 1) -----------
//
// Cannot be produced by the stub above (it always answers 200), so it is checked against
// the component contract: the loading and error branches must never coexist in the DOM.
await visit('/shifts/?state=unresolved', 1280, 900)
const exclusive = await evalJson(`JSON.stringify({
  states: [...document.querySelectorAll('.data-state')].map(n => n.className),
})`)
record(
  'at most one .data-state region is rendered at a time',
  exclusive.states.length <= 1,
  JSON.stringify(exclusive.states),
)

await page.close()
try { chrome.child?.kill?.() } catch {}
srv.close()

const failed = results.filter((r) => !r.ok)

if (mutation !== null) {
  if (!mutationApplied) {
    process.stdout.write(`\nMUTATION "${mutation}" NEVER APPLIED — this run proves nothing.\n`)
    process.exit(2)
  }
  // Under a mutation the expected outcome is INVERTED: at least one probe MUST go red.
  // A green run here means the probe measures nothing and should be deleted or rewritten.
  const ok = failed.length > 0
  process.stdout.write(
    ok
      ? `\nmutation "${mutation}": ${failed.length} probe(s) went RED, as they must.\n`
      : `\nmutation "${mutation}": every probe stayed GREEN — the probes prove nothing.\n`,
  )
  process.exit(ok ? 0 : 1)
}

process.stdout.write(
  failed.length === 0
    ? `\nAll ${results.length} layout probes passed.\n`
    : `\n${failed.length} of ${results.length} layout probes FAILED.\n`,
)
process.exit(failed.length === 0 ? 0 : 1)
