# UX audit — the admin panel as it actually is

Date: 2026-08-12 · Scope: `web/app/**/page.tsx` at commit-in-tree · **No code was changed.**

What this is: every route, every reachable state, screenshotted at 390px and 1280px against a
stubbed API, plus what the external keys are really doing on the VM. Reality, not intent —
where a code comment claims a problem is solved and the pixels say otherwise, the pixels win.

- **96 screenshots**, 48 states × 2 widths → `docs/media/states/<screen>-<state>-<width>.png`
- Harness: `/tmp/statesshot.mjs` — static server over `web/out` + stubbed `/admin/*`, driven by
  `demo/cdp.mjs`. No new dependency. **Never pointed at production.**
- Mutation probe: `/tmp/probe.mjs` — proves two load-bearing claims go RED then GREEN.
- Production was touched **read-only**: `ssh`, `systemctl cat`, `SELECT`. No writes.

---

## The ten worst

### 1 · Every admin screen shows an error AND "Wird geladen…" forever, with no retry

`docs/media/states/dashboard-error-500-1280.png` · `shifts-error-500-1280.png` ·
`payroll-error-500-1280.png` · `workers-error-500-1280.png`

A 500 on first load renders the red error line **and then the loading text, permanently**,
because the loading branch is keyed on `snapshot === null` and a failed load never sets it.

```tsx
// web/app/page.tsx:184
{snapshot === null ? (
  <p role="status">{t('loading')}</p>
) : (
```

Identical at `web/app/shifts/page.tsx:827`, `web/app/payroll/page.tsx:281`,
`web/app/pl/page.tsx:387`, and the same shape on the other seven screens.

Worse: on the dashboard the only reload control is the **"Aktualisieren" button inside the
`snapshot !== null` branch** (`web/app/page.tsx:229`), so on a failed first load there is
literally no control on the page. The way out is F5.

Count of admin screens with a data-load retry control: **1 of 11** — and `/analytics/`'s
button (`analytics/page.tsx:436`) retries the *map*, not the report.

| screen | error shown | still says "loading" | retry control |
|---|---|---|---|
| all 11 admin screens | ✓ | ✓ | ✗ (analytics: map only) |

∴ a director hitting a transient 500 sees "something broke, and it is still trying" — which is
false — and has no affordance. Dead end on every screen.

### 2 · Payroll's reconciliation warning is hard-coded to the wrong direction, and the CSV carries none of it

`docs/media/states/payroll-overlimit-reconcile-1280.png`

Server aggregate **1.093,25 €**, rows on screen **121.334,00 €**, and the screen says:

> „…Die Differenz ist Arbeit, die in der Datenbank steht, aber wegen der Zeilenbegrenzung
> nicht an diese Seite übermittelt wurde. **Diese Summe ist daher zu niedrig.**"

The sentence is one fixed string; the sign of the difference is never read:

```ts
// web/lib/payroll.ts:180
return { serverCents, visibleCents, missingCents: serverCents - visibleCents }
```
```tsx
// web/app/payroll/page.tsx:323
{reconciliation.missingCents !== 0 ? (
  <li>{t('caveatReconcile', { server: money(...), visible: money(...) })}</li>
```
`payroll.caveatReconcile` (de.json) ends `"Diese Summe ist daher zu niedrig."` unconditionally.

Two compounding facts in the same screenshot:
- The `caveatTruncated` line — the only one that names the 2000-row cap — is suppressed,
  because `periodExceedsCoverage` is false whenever the truncated tail still reaches back past
  the period start (`web/app/payroll/page.tsx:315`, `web/lib/payroll.ts:161`).
- The **`Gesamt` row is bold, unmarked, and "CSV herunterladen" is enabled**
  (`web/app/payroll/page.tsx:440`). `downloadCsv` writes headers + lines + total and **no
  caveat, no truncation flag, no reconciliation line** (`web/app/payroll/page.tsx:182-200`).

∴ the file the accountant pays from can contain a number the screen has already worked out is
wrong, described in the wrong direction, with the cap notice hidden. ⚠ Highest money risk here.

### 3 · Desktop tables collapse to one character per column — `overflow-wrap: anywhere`

`docs/media/states/workers-populated-1280.png` (headers render vertically: `S T U N D E N S A T Z`)
· `locations-populated-1280.png` (`KUND E UND ANSP RECH PERS ON`, addresses broken mid-word)
· `pl-populated-flagged-1280.png` (`1.091, 25 €` broken mid-number) ·
`contracts-history-open-1280.png` (`1.20 0,00 €`) · `analytics-map-nokey-1280.png`

```css
/* web/app/globals.css:360 (and :418) */
.data-table th,
.data-table td {
  /* Long German compounds and long relay addresses break rather than overflow. */
  overflow-wrap: anywhere;
}
```

`anywhere` — unlike `break-word` — **contributes to min-content width**. Every text column's
minimum becomes 1ch, so any incompressible cell (a `<code class="code-block">` tag URI, a
`white-space: nowrap` `.cell-actions` button group) takes the width and the rest are crushed.

**Mutation test, `/tmp/probe.mjs` §A** — swap only that one property at runtime on `/workers/`:

```
as shipped   Name=54  E-Mail=60  Telefon=68  Stundensatz=51  Status=42 | Zugangscode=477  Aktionen=270
break-word   Name=80  E-Mail=158 Telefon=94  Stundensatz=127 Status=78 | Zugangscode=477  Aktionen=269
five text columns together: 275px -> 537px (1.95x)
VERDICT: CONFIRMED — that one property costs 1.95x the text width
```

Money broken across lines mid-digit-group (`1.20` / `0,00` / `€`) on a contract-price column is
not cosmetic. Desktop-first is the project's own target (decision-7, as amended by
decision-28); at 1280px the two most-used screens are illegible.

### 4 · The Google Maps browser key is provisioned but was never installed — the map can never draw in production

`docs/media/states/analytics-map-nokey-1280.png` — the whole „Karte" section is a blue box
reading „Dieser Build enthält keinen Google-Maps-Schlüssel".

This is not a fixture artefact; it is production:

```
psst list                              → NEXT_PUBLIC_GOOGLE_MAPS_KEY [browser, vercel]   ✓ provisioned
rg NEXT_PUBLIC ops/deploy.sh           → only NEXT_PUBLIC_DEFAULT_LOCALE=de              ✗ never passed
grep -rl AIza /srv/nfc/public          → (nothing)                                       ✗ not in bundle
grep -o 'let d=…' …/chunks/fbf7db….js  → process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY??""     → ""
```

`ops/deploy.sh:44` is the whole build line:
`(cd web && pnpm install --frozen-lockfile && NEXT_PUBLIC_DEFAULT_LOCALE=de pnpm verify)`

∴ `MAPS_API_KEY === ''` (`web/lib/map.ts:24`) forever → `mapStatus = 'noKey'` forever
(`analytics/page.tsx:184`) → **and every Street View thumbnail returns null**
(`web/lib/map.ts:238`, first guard). The panel degrades honestly, which is the good part; the
bad part is that a paid, restricted key has sat unused since the screen shipped. This is the
exact pattern the brief names.

### 5 · Sentry is dead twice over on the VM

The DSN is unset **and** the running process never loads the instrumentation:

```
/etc/nfc/env                     APP_KEY, DATABASE_URL, GOOGLE_GEOCODING_KEY, PORT   (no SENTRY_DSN)
ps -eo args | grep server.js     /usr/bin/node /srv/nfc/server.js
```

The repo's own unit file says the flag is not optional:

```ini
# ops/systemd/nfc-api.service
# --import is REQUIRED, not a style choice … Dropping the flag silently loses all tracing.
ExecStart=/usr/bin/node --import /srv/nfc/instrument.mjs /srv/nfc/server.js
```

The **installed** unit (`systemctl cat nfc-api`) is a different, older file:
`ExecStart=/usr/bin/node /srv/nfc/server.js`, `User=exedev`, no hardening beyond four lines.
`/srv/nfc/instrument.mjs` is deployed and never executed.

∴ setting `SENTRY_DSN` alone would fix nothing. decision-23 is not in force in production.
Not a UI finding, but it is why nobody can see any of the findings above happening to the
director. `ops/deploy.sh` never installs or reloads the unit.

### 6 · P&L totals row does not add up to the column above it

`docs/media/states/pl-populated-flagged-1280.png`

`ARBEIT` column reads 471,25 + 620,00 + 120,00 = **1.211,25 €**. `Gesamt` reads **1.091,25 €**.

```ts
// web/lib/pl.ts:142-149
if (building.revenue_cents === null) {
  totals.unpricedBuildings += 1
  totals.costCentsUnpriced += building.labour_cents + building.material_cents
} else {
  totals.revenueCents += building.revenue_cents
  totals.labourCentsPriced += building.labour_cents   // ← unpriced buildings' labour dropped
```

The only explanation on screen is the sub-label „2 Objekte mit Vertrag" under the word
`Gesamt` (`web/app/pl/page.tsx:559`). An accountant checks the addition of a labour column
before anything else; it fails, and the reason is a five-word gloss in a different cell.

### 7 · The mobile totals row is four unlabelled numbers

`docs/media/states/pl-populated-flagged-390.png` — the last card reads
`Gesamt 1.880,00 € · 2 Objekte mit Vertrag · 1.091,25 € 51,60 € 737,15 € 39,21 %`.

Column headings are visually hidden below 768px and re-printed per cell from `data-label` —
but only for `tbody`:

```ts
// web/components/ResponsiveTableLabels.tsx:25
for (const row of table.querySelectorAll('tbody tr')) {
```

The CSS knows and shrugs:

```css
/* web/app/globals.css:1041 */
/* The totals row is a row of numbers with no headings of its own … */
.data-table tfoot tr { display: flex; flex-wrap: wrap; … }
```

On a phone the director cannot tell Umsatz from Arbeit from Material from Ergebnis. Same on
`payroll-populated-390.png`. decision-28 says the panel works on a phone; the one row a
director quotes down the phone is the row that does not.

### 8 · An empty database reads as an all-clear

`docs/media/states/dashboard-empty-1280.png` · `dashboard-empty-390.png`

With zero workers, zero buildings and zero shifts the landing page says, in bold:

> **„Nichts zu tun. Zurzeit ist niemand eingestempelt."**
> · „Keine Schicht wartet auf Bestätigung." · „Alle aktiven Mitarbeiter haben eine
> Anmeldeadresse hinterlegt." · **„Zu jedem aktiven Objekt ist mindestens eine Schicht erfasst."**

All four are vacuously true over empty sets. `/shifts/`, `/payroll/` and `/locations/` were all
hardened against exactly this reading (their own comments say so, at length) — the **dashboard,
the page the director actually lands on, was not**. `problemCount` counts three fixed
categories (`web/app/page.tsx:196`) and none of them can ever fire on an empty database.

There is also no onboarding path: nothing on the page links to „Mitarbeiter anlegen" or
„Objekt anlegen" when there are none.

### 9 · Rarely-used create forms sit on top of the lists that are the point of the screen

`docs/media/states/shifts-populated-1280.png` — the Schichtprotokoll starts **1030px down**,
under a filter bar, a manual-entry form with four fields, and a correction section.
`shifts-populated-390.png` — the log starts **~1900px down**; on a phone that is five swipes
before the first shift.

Same order on `/workers/` (form → 730px), `/locations/` (form → 830px, `locations-populated-1280.png`),
`/inventory/`, `/clients/`. The form is always expanded, never a disclosure.

The screens are documented as verification screens („diese Liste daher vor jeder
Lohnabrechnung prüfen" — `shifts.intro`) and are laid out as data-entry screens.

### 10 · Internal ADR identifiers are printed to the operator

`docs/media/states/pl-populated-flagged-1280.png` („…verteilt (decision-6)…" and
„…unberücksichtigt (decision-10)…") · `contracts-history-open-1280.png` („(decision-28)") ·
`analytics-map-nokey-1280.png` · `materials-populated-1280.png`

Six user-facing strings, in **both** locales, carry an ADR id:

```
materials.noteAttribution   materials.locationHint   pl.methodMaterials
pl.methodExclusions         contracts.noteLabourNoHistory   analytics.noteExclusions
```

A Viennese cleaning-company director has no way to resolve „decision-6". It reads as an error
code and invites a support call about a sentence that is otherwise well written.

---

## 1 · Route inventory

13 files under `web/app/**/page.tsx` (12 routes + `not-found.tsx`). `PRIMARY_NAV`
(`web/lib/nav.ts:19`) lists 11; `/login/` and `/reinigung/` are deliberately outside it.

| route | job in one sentence | reads | actions | links out | **should link and does not** |
|---|---|---|---|---|---|
| `/` dashboard | „is anything wrong right now, and did anyone tap at all?" | `GET /admin/data?limit=2000` | refresh | `/shifts/`, `/workers/`, `/locations/` | **`/material-requests/`** — 1 request waiting on a decision is a today-problem and never appears here; **`/payroll/`**; nothing on an empty DB |
| `/shifts/` | the ledger, and the only place to fix it | `GET /admin/data?limit=2000` | `POST /admin/shifts`, `PATCH /admin/shifts/:id`, filter by worker/building/period | — (none) | `/payroll/` (the screen it exists to unblock), `/workers/`, `/locations/` |
| `/material-requests/` | the queue a worker is standing in a building waiting on | `GET /admin/data` | `PATCH /admin/material-requests/:id` (status + paperwork) | `/pl/`, `/inventory/` | `/` (nothing brings the director here), `/locations/` |
| `/workers/` | create, edit, lock out the people who file hours | `GET /admin/data` | `POST /admin/workers`, `POST`/`DELETE …/enrolment-code` | — (none) | `/shifts/` (their hours), `/payroll/` (their pay) |
| `/locations/` | everything about one building, incl. the NFC tag string | `GET /admin/data?limit=2000` | `POST /admin/locations`, `DELETE …` (deactivate+revoke), `POST /admin/portal-grants`, `DELETE …`, clipboard | `/clients/` | `/contracts/` (price history — the mirrored price is shown here), `/analytics/`, `/shifts/` filtered to the building |
| `/clients/` | tidy up companies and their contacts | `GET /admin/data` | `POST`/`DELETE` clients + contacts | `/locations/` | `/contracts/` |
| `/inventory/` | products and equipment with unit cost | `GET /admin/data` | `POST /admin/inventory` | — (none) | `/material-requests/` (the only consumer of this catalogue) |
| `/contracts/` | what a building was priced at, when | `GET /admin/data`, `GET /admin/locations/:id/contracts` | `POST …/contracts`, `DELETE /admin/contracts/:id` | `/locations/`, `/pl/` | `/analytics/` (the target minutes it sets) |
| `/payroll/` | what to pay each person for a period | `GET /admin/data?limit=2000&from&to` | period select, CSV download | `/shifts/` ×4 | `/workers/` (to fix a rate), `/pl/` |
| `/pl/` | revenue − labour − material per building | `GET /admin/pl?from&to`, `POST`/`DELETE /admin/settings` | set/clear margin baseline | `/material-requests/`, `/contracts/`, `/shifts/` | `/payroll/` (same labour, different screen), `/analytics/` |
| `/analytics/` | agreed vs actual time, trend, map | `GET /admin/analytics?from&to&months`, `POST …/geocode` | retry geocode, open detail panel, map retry | `/contracts/`, `/shifts/`, `/locations/` | `/pl/` |
| `/login/` | email + password → session cookie (decision-20) | — | `POST /admin/login` | — | — (correct: no chrome by design) |
| `/reinigung/` | a client contact reads their own building's record | `GET /portal/:token` | retry | — | — (correct: no path into the admin app) |

Cross-cutting: **`GET /admin/session` exists (`server/routes/admin.js:1276`) and no web code
calls it.** The panel discovers a dead session only by failing a data fetch and then
`router.replace('/login/')`. There is no session pre-check and no "your session expired"
message on the login screen — the user is simply teleported.

## 2 · State matrix

Every state below was reproduced and captured at **both** 390px and 1280px. File pattern:
`docs/media/states/<name>-390.png` and `-1280.png`.

| screen | state | screenshot name | reachable in production? |
|---|---|---|---|
| dashboard | loading | `dashboard-loading` | ✓ every load |
| | empty (first run) | `dashboard-empty` | ✓ — finding 8 |
| | populated w/ problems | `dashboard-populated` | ✓ |
| | error 500 | `dashboard-error-500` | ✓ — finding 1 |
| | 401 expired → `/login` | `dashboard-401-redirect` | ✓ (session TTL) |
| | over-limit 2000 rows | `dashboard-overlimit` | ⚠ contrived — live DB has 8 shifts; needs ~2000 |
| shifts | loading | `shifts-loading` | ✓ |
| | empty database | `shifts-empty-database` | ✓ first run only |
| | empty *filter*, rows exist outside | `shifts-empty-filtered` | ✓ — handled well, see §4 |
| | populated, all 4 shift states + manual | `shifts-populated` | ✓ |
| | truncated at 2000 | `shifts-overlimit` | ⚠ contrived |
| | error 500 | `shifts-error-500` | ✓ |
| | correction form open | `shifts-correction-form` | ✓ |
| workers | empty / populated / 500 | `workers-empty`, `workers-populated`, `workers-error-500` | ✓ |
| | fresh enrolment code panel | **not captured** | ⚠ needs a real `POST` round trip; stub returns no code |
| locations | empty / populated | `locations-empty`, `locations-populated` | ✓ |
| | chosen month has no time | `locations-month-empty` | ✓ (any month before the first shift) |
| | truncated at 2000 | `locations-overlimit` | ⚠ contrived |
| | fresh client link panel | **not captured** | ⚠ needs a real mint |
| clients | empty / populated | `clients-empty`, `clients-populated` | ✓ |
| inventory | empty / populated | `inventory-empty`, `inventory-populated` | ✓ |
| materials | empty open queue (good day) | `materials-empty-queue` | ✓ |
| | populated, all 5 lifecycle stages | `materials-populated` | ✓ |
| | detail/paperwork form | `materials-detail-form` | ✓ |
| | truncated at 500 | **not captured** | ⚠ contrived; needs 500 requests |
| contracts | no buildings | `contracts-no-buildings` | ✓ first run |
| | buildings listed, none selected | `contracts-populated` | ✓ |
| | history open, 3 periods + current | `contracts-history-open` | ✓ |
| payroll | loading | `payroll-loading` | ✓ every period change |
| | period empty, rows exist elsewhere | `payroll-empty-period` | ✓ |
| | populated | `payroll-populated` | ✓ |
| | reconciliation mismatch | `payroll-overlimit-reconcile` | ⚠ contrived — **but this is finding 2** and it is reachable the day the crew grows |
| | error 500 | `payroll-error-500` | ✓ |
| P&L | populated, 1 flagged, 1 not-assessable | `pl-populated-flagged` | ✓ |
| | baseline unset (shipped default) | `pl-no-baseline` | ✓ — `app_settings` is empty in production |
| | no buildings in period | `pl-empty` | ✓ |
| | error 500 | `pl-error-500` | ✓ |
| analytics | map `noKey` + table | `analytics-map-nokey` | ✓ **this is the only state production can reach** — finding 4 |
| | detail panel + trend | `analytics-detail-panel` | ✓ |
| | no buildings | `analytics-empty` | ✓ |
| | map `ready` / `blocked` / `failed` / `noPins` | **unreachable** | ✗ requires a key in the bundle; four of five map states are dead code today |
| login | idle / failed | `login-idle`, `login-failed` | ✓ |
| portal | populated / empty / invalid link / no token | `portal-populated`, `portal-empty`, `portal-invalid-link`, `portal-no-token` | ✓ |
| portal | 429 rate-limited | **not captured** | ⚠ same render path as `linkInvalid`, distinct message |

**Unreachable without contrived data:** every `shift_limit`/`material_request_limit`
truncation state (live DB: 8 shifts), the payroll reconciliation mismatch, and **four of the
five map states** (`ready`, `blocked`, `failed`, `noPins`) which cannot occur while the build
has no key. `analytics-map-nokey` is the production reality.

## 3 · Config and key gaps

| dependency | provisioned | wired into running code | present on the VM | verdict |
|---|---|---|---|---|
| `GOOGLE_GEOCODING_KEY` (server) | ✓ psst `[server]` | ✓ `server/lib/geocode.js:56` | ✓ `/etc/nfc/env` + in the process env | ✓ live — **but see below** |
| `NEXT_PUBLIC_GOOGLE_MAPS_KEY` (browser) | ✓ psst `[browser, vercel]` | ✓ `web/lib/map.ts:24` | ✗ **not passed by `ops/deploy.sh:44`; no `AIza` anywhere in `/srv/nfc/public`** | ✗ **provisioned, never installed** — finding 4 |
| `SENTRY_DSN` | ✗ not in the vault at all | ✓ `server/instrument.mjs:31` | ✗ not in `/etc/nfc/env` | ✗ dead |
| Sentry instrumentation flag | n/a | ✓ in `ops/systemd/nfc-api.service` | ✗ **installed unit is `node /srv/nfc/server.js`, no `--import`** | ✗ dead even if the DSN appeared — finding 5 |
| `SENTRY_ENVIRONMENT` / `SENTRY_RELEASE` | ✗ | ✓ | ✗ | moot |
| Sentry on iOS (decision-23) | — | — | — | **not verified in this audit** |
| Street View Static API | key would be the browser key | ✓ `web/lib/map.ts:238` | ✗ (no key) + the API is documented as not enabled on the Cloud project | ✗ two independent blockers |
| Twilio / SMS / push | ✗ nothing in the repo | ✗ | ✗ | correct — decision-23 forbids it; `/material-requests/` copy says so explicitly ✓ |
| `APP_KEY`, `DATABASE_URL`, `PORT` | ✓ | ✓ | ✓ | ✓ |
| `ADMIN_PIN` | still in the vault `[legacy-only]` | ✗ removed (decision-20) | ✗ | ⚠ stale vault entry, harmless |

**The aftermath of the geocoding gap is still on screen.** The key is installed now, but the
one production building was geocoded before it was:

```
slug                      pinned  geocode_status  geocoded_at
hoiv-arsenalstrasse-11    f       no_key          2026-08-11 23:37:47+00
```

So `/analytics/` reports „Konnte nicht verortet werden (no_key)" for the only building in the
system, permanently, until somebody presses „Erneut verorten". Nothing re-runs it: there is no
backfill on deploy (`server/bin/geocode-backfill.js` exists and is not called by
`ops/deploy.sh`), and `no_key` is not distinguished on screen from a real Google failure —
`geocodeText()` (`analytics/page.tsx:296`) prints the raw status either way.

**Database sanity (read-only):** migrations `001`–`005` all applied; 14 tables; 8 shifts,
4 workers, 1 location — matches the brief. `app_settings` is empty, so `pl_margin_baseline_bp`
is unset and `/pl/` flags nothing in production (`pl-no-baseline-*.png` is the live state).

## 4 · Where the admin is overwhelmed or given an unclear answer

**Dense tables**
- `/locations/` — 8 columns, and one of them („Vertrag und Zeit im gewählten Monat") carries
  **five separate facts**: price, actual time, target, over/under delta, pending count
  (`locations/page.tsx:1090-1105`). At 1280px every other column is one character wide.
- `/workers/` — 7 columns; the „Zugangscode" cell holds a status sentence plus two buttons and
  takes 477px of 1080, leaving 275px for the other five columns combined (measured).
- `/pl/` — 8 columns, three of which can each render one of three different „unknown" phrasings.
- `/shifts/` — 8 columns; on a phone each row becomes a 7-line card, so 12 shifts is ~2300px.

**Unexplained or wrong numbers**
- P&L `Gesamt` labour ≠ the sum of the labour column (finding 6).
- Payroll `Gesamt` presented as the answer while the callout above says it is wrong (finding 2).
- Dashboard heading „Zuletzt erfasste Schichten (die letzten 10)" over **9 rows** — open and
  unresolved shifts are filtered out after the heading's count is fixed at
  `RECENT_SHIFTS = 10` (`web/app/page.tsx:42, 147, 302`). The number in the heading is a
  constant, not a count.
- `/locations/` defaults its time column to the **current, incomplete month** and then asserts
  a contract shortfall against it: on 12 August the HOIV row reads „Sollzeit 40:00. Das sind
  40:00 unter der Sollzeit." (`targetSentence`, `locations/page.tsx:583`). The month picker
  added to fix this did not change the default or qualify the sentence.
- `/shifts/` shows an auto-closed shift's stub duration as a plain „8:00" in the Dauer column;
  only the Status cell reveals it is a machine guess (`shifts-populated-1280.png`, row 3).

**Jargon**
- „decision-6", „decision-10", „decision-28" printed in six user-facing strings (finding 10).
- „Zeilenbegrenzung", „Relay-Adresse", „basis points" rendered as „Zielmarge in Prozent … –5
  bedeutet höchstens 5 % Verlust" (that last one is *good* — it explains itself).
- „Sollzeit", „Vertragsvolumen", „Kurzkürzel", „Zugangscode", „Kundenlink" are five different
  nouns for five different things on one screen with no glossary.

**States that look like data loss**
- Empty database on the dashboard reads as an all-clear (finding 8).
- Error + eternal „Wird geladen…" reads as *still working* rather than *failed* (finding 1).
- ✓ **Handled well and worth keeping:** `/shifts/` empty-filter state
  (`shifts-empty-filtered-1280.png`) says how many rows the period is hiding, names the date of
  the newest shift, and offers two one-click escapes. `/payroll/` and `/locations/` do the same.
  This is the strongest thing in the panel.

**Dead ends**
- Every data-load error, on every admin screen (finding 1).
- `/material-requests/` — „Ablehnen" is a single unconfirmed click and `rejected` is terminal
  (`web/lib/materials.ts:20` → `nextStatuses('rejected') === []`, so no button is ever drawn
  again). The screen's own hint says „Beides ist endgültig". No confirm, no undo.
- `/contracts/` — „Diese Periode rückgängig machen" on the current period is likewise
  unconfirmed and silently reopens the predecessor period, changing an already-reported month.
- `/analytics/` — with no map key, the „Karte" heading, the status box and the hidden canvas
  occupy the top of the screen permanently to say nothing.
- `/login/` — a 401 bounce arrives with no explanation of why; the login screen shows its idle
  state as if the user had navigated there on purpose.

**Layout collisions**
- `analytics-map-nokey-1280.png`, last row: the „Erneut verorten" button **overlaps** the
  sentence „Nie verortet – keine Adresse, oder es hat noch niemand danach gefragt".
  `.cell-actions { white-space: nowrap }` (`globals.css:390`) inside a wrapping cell.

## 5 · What was checked and found FINE (so nobody re-audits it)

- **No horizontal page scroll at 390px on any of the 48 states.** `document.scrollWidth >
  innerWidth` was false everywhere. decision-28's card transform holds.
- **No sub-44px touch target at 390px on any state.** (13–34 controls per page are under 44px
  at 1280px; that is a mouse target and not a defect.)
- **`data-label` coverage is 100% of `tbody` `<td>`** on every populated table
  (e.g. `shifts-overlimit-390`: 791/791) and the labels are *correct* — the off-by-one that
  once captioned a timestamp „Objekt" is fixed (`ResponsiveTableLabels.tsx:31`).
- **de/en key parity is exact: 814/814**, zero keys on either side only. No bare JSX literal
  found on any captured screen.
- **`ResponsiveTableLabels` is not a performance problem.** Measured, `/tmp/probe.mjs` §B:
  12 shifts → 84 cells → 146 ms first paint; 2000 shifts → 14 000 cells → 383 ms. 2.6×, not
  the O(n²) hazard the `MutationObserver` looks like. Claim retracted before it was made.
- **The client portal is clean** at both widths, in all four states, with no admin chrome and
  no path back into the panel (`portal-*.png`).
- **Sign-in has no account oracle** — one message for unknown email and wrong password
  (`login/page.tsx:44`), confirmed on `login-failed-*.png`.

## 6 · Reproducing this

```bash
cd web && NEXT_PUBLIC_DEFAULT_LOCALE=de pnpm build     # match the production bundle
node /tmp/statesshot.mjs                               # all 48 states x 2 widths
node /tmp/statesshot.mjs '^payroll'                    # one screen
ONLY_W=390 node /tmp/statesshot.mjs '^pl-'             # one width
node /tmp/probe.mjs                                    # the two mutation tests
```

The harness binds `127.0.0.1:8099`, serves `web/out`, and answers `/admin/*` and `/portal/*`
from an in-process fixture whose `status` and `delayMs` the driver sets per scenario. It has no
production hostname in it. Both scripts are throwaway; nothing in the repo was modified.

**Not done, and it matters:**
- iOS and Android app UI — out of scope, not looked at.
- Real-browser accessibility audit (axe/contrast ratios) — only structure, focus order and
  landmark use were read from source; **no contrast measurement was made.**
- Sentry-on-iOS wiring — not verified.
- Keyboard-only walkthrough of the enrolment-code and client-link panels — those two states
  could not be reached through the stub.
- No load test, no real-device test, no test with a real Google Maps key.
