# Simulation report — a cleaning company grown for twelve months

**What this is.** `demo/simulate.mjs` seeds and drives an invented Vienna cleaning company
against the **`nfc_demo`** database, then measures the product against it. It is a load test
and an operational audit at once, because the two questions are the same question: the
system does not fall over at scale, it goes on answering, and the answers stop being true.

**Production was not touched.** Every number below comes from `nfc_demo` on this machine.
The guards that make that a fact rather than a promise are in §4, together with the
mutations that prove they fail when removed.

```
DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs                # 12 months
DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --months 24    # the stress case
DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --self-check   # the arithmetic
```

Deterministic: seed `20260815`, so every figure here is reproducible.

---

## The verdict in one paragraph

Nothing is slow. The heaviest query in the product answers a two-year, 14 639-shift ledger
in **166 ms**. What breaks is not the server, it is the **2000-row cap on `/admin/data`**,
which three screens hit while continuing to render numbers that read as complete. At the
size the simulated company reached in **month 9** the dashboard reported **22 shifts need
confirming** when the database held **37**; the missing 15 are **€1 658,88 of unpaid hours**
that no screen in the panel can reach. Run the same company for 24 months and it is **113
versus 13**, and **€11 986,40**. Two of the thirteen unexpected events the simulation injects
have no procedure in the app at all, and one of them — a tap on the wrong building's tag —
is not merely unprocedured but **undetectable**: €732,23 of labour in year one is booked to
a building nobody cleaned, and no query in the system can find it.

---

## 1. Where does it break or crawl?

### 1.1 The company

Twelve months to 2026-08-12, seed `20260815`:

| | rows |
|---|---|
| shifts | **3 703** (1 224 kB on disk) |
| workers | 14 (11 active) |
| buildings | 30 (27 active) |
| clients | 11 |
| contract rows (`location_contracts`) | 44 |
| material requests | 26 |

### 1.2 Per month — volume, timing, payload

`/admin/data` is called with `?limit=2000&from=&to=` for the month, exactly as the payroll
screen calls it. `/admin/pl` with the same period. Timings are the median of three runs of
the **real route handlers**, imported from `server/routes/admin.js` — not a re-implementation
of their SQL, so a regression in the server is a regression here.

| month | shifts | cumulative | workers | buildings | `/admin/data` | payload | `/admin/pl` | payroll drift |
|---|---|---|---|---|---|---|---|---|
| 2025-08 | 98 | 98 | 3 | 4 | 1,8 ms | 73 kB | 1,1 ms | €207,86 |
| 2025-09 | 115 | 213 | 3 | 5 | 1,5 ms | 80 kB | 0,8 ms | €201,70 |
| 2025-10 | 135 | 348 | 3 | 6 | 1,2 ms | 88 kB | 1,1 ms | €250,31 |
| 2025-11 | 145 | 493 | 2 | 8 | 1,3 ms | 92 kB | 0,7 ms | €337,29 |
| 2025-12 | 245 | 738 | 2 | 9 | 1,5 ms | 131 kB | 0,9 ms | €625,99 |
| 2026-01 | 278 | 1 016 | 3 | 11 | 1,6 ms | 144 kB | 0,9 ms | €198,68 |
| 2026-02 | 277 | 1 293 | 2 | 13 | 1,6 ms | 144 kB | 0,8 ms | €250,62 |
| 2026-03 | 370 | 1 663 | 5 | 16 | 1,8 ms | 181 kB | 1,0 ms | €350,73 |
| **2026-04** | 396 | **2 059** | 5 | 18 | 1,9 ms | 192 kB | 1,0 ms | €217,74 |
| 2026-05 | 439 | 2 498 | 7 | 22 | 1,9 ms | 209 kB | 1,1 ms | −€0,17 |
| **2026-06** | **568** | 3 066 | 8 | 25 | 2,4 ms | 262 kB | 1,5 ms | €88,96 |
| 2026-07 | 636 | 3 702 | 9 | 27 | 2,4 ms | 288 kB | 1,3 ms | −€0,29 |

Year P&L over all 12 months: **6,7 ms / 18 kB**. Year analytics with a 24-month trend:
**47 ms / 56 kB**. Write throughput: 3 703 shifts inserted in **237 ms**.

**Nothing crawls.** Postgres is not the constraint and will not be for years.

### 1.3 At how many workers / buildings / months is the 2000 cap actually hit?

Two different limits, and only one of them is the one people talk about.

**a) The per-period limit — 500 default, 2000 maximum.**
A single month first exceeds the server's **500 default** in **2026-06, month 11**, at
**8 workers / 25 buildings / 568 shifts**. It never reaches 2000 in a month within a year.
The panel does not use the default — `web/lib/api.ts:383` sets `ADMIN_SHIFT_LIMIT = 2000` on
every call — so this bound is only reachable by an API client that omits `limit`.

**b) The limit that actually bites — 2000 rows on the UNBOUNDED fetch.**
Three screens fetch with **no period at all**:

| screen | call | file |
|---|---|---|
| Dashboard | `/admin/data?limit=2000` | `web/lib/api.ts:563` |
| Shift log | `/admin/data?limit=2000` | `web/lib/api.ts:452` |
| Buildings | `/admin/data?limit=2000` | `web/lib/api.ts:645` |

The shift log does this deliberately — it has to be able to say *"no shifts in August, 5
exist in earlier periods"*, and a server-bounded fetch cannot (`web/lib/api.ts:438-446`).
The consequence is that all three become a **rolling window of the most recent 2000 shifts**.

```
cumulative shifts pass 2000 in 2026-04  →  month 9 of 12, 5 workers, 18 buildings
```

**From month 9 onward the window shrinks every month, because the company grows:**

| | window |
|---|---|
| at 636 shifts/month (month 12) | **3,1 months** of history |
| at 1 330 shifts/month (24-month run) | **1,5 months** |
| at twice that | **0,8 months** — less than one payroll period |

Measured at the end of the 12-month run: the unbounded payload is **833 kB, 9,7 ms, 2000/2000
rows**, and it **holds the last 131 days of a 376-day ledger**.

### 1.4 What the director sees when it is hit

This is the part that matters, and it is measured rather than argued: `demo/simulate.mjs`
reproduces the dashboard's own arithmetic from `web/app/page.tsx:116-140` and diffs it
against SQL over the whole table.

| | 12 months | 24 months |
|---|---|---|
| dashboard says "shifts need confirming" | **22** | **13** |
| database holds | **37** | **113** |
| hidden, in unpaid hours | **€1 658,88** | **€11 986,40** |
| shift-log months that render EMPTY though they hold shifts | 8 | 22 |
| active buildings flagged "tag may be missing or never written" | 2 | 2 |
| ...of which have genuinely never had a shift | **1** | **1** |

Three concrete things the director sees:

**(i) An undercount that reads as a count.** `home.unresolvedSome` renders
*"22 shifts were closed by the 8-hour timer and are not paid until they are confirmed."*
There is no "at least". The truncation note under the triage list
(`home.truncatedNote`) says *"Only the 2000 most recent shifts were loaded, **so a building
last cleaned a long time ago can appear above by mistake**"* — it warns about the dead-tag
false positive and says nothing about the unresolved undercount, which is the one with money
attached. The note is right about the wrong item.

**(ii) A dead-end link.** Verified against the live handlers, not by reading the code:

```
payroll 2025-11: 145 rows loaded, 2 unresolved   → screen offers „Confirm them now"
link target: /shifts/?state=unresolved&period=all   (web/app/payroll/page.tsx:329)
shift log loads unbounded, window starts 2026-04-03
of those 2 November shifts, reachable on the shift log: 0
```

Payroll fetches **with** a period, so it sees old months correctly and correctly reports the
caveat. The shift log fetches **without** one. The link therefore lands on a screen that
cannot show the rows the previous screen just counted, and `period=all` makes it look as
though it should. **The 15 hidden unresolved shifts of year one are unreachable from every
screen in the panel.** They are excluded from payroll by `decision-10` forever.

**(iii) A check whose label stopped matching its question.** `locationsWithoutShifts`
(`web/app/page.tsx:135-140`) computes *"active building absent from the loaded shift list"*
and labels it *"has no recorded shift, so its tag may be missing or never written"*. Below
2000 total shifts those are the same question. Above it they are not: at 12 months it flags
2 buildings, of which 1 has genuinely never had a tag written and 1 —
`Wohnhausanlage Ottakringer 74`, last cleaned 2026-03-31 — simply fell out of the window.
Today that second one happens to be the building whose tag really did die, so the alert is
accidentally correct. A quiet 2×/week building would be flagged identically and be perfectly
healthy.

### 1.5 Payload size is the other cost

**833 kB of JSON on the dashboard**, every load, on a panel that now ships to phones
(decision-29). Nothing on the dashboard needs 2000 shift rows: it renders the open shifts,
a count, and the last few completed shifts. It downloads a rolling four months of the
company to compute two integers.

---

## 2. For every unexpected event, what procedure does the app suggest?

Thirteen event classes are injected and counted. `assertEventsFired()` throws if any of them
produced zero occurrences, so no row below is written about something that did not happen.

**Order of the fix, as required: in-app guidance → help page or manual → onboarding or
feature video → FAQ. A phone number is the last resort and appears nowhere below.**

Ordered by consequence.

### ▲ 1 — Tap at the wrong building (25 shifts, €732,23) — NO PROCEDURE, AND UNDETECTABLE

**What the app says: nothing.** There is no string anywhere in `web/messages/en.json` or
`de.json` about a shift being recorded against the wrong building. There is no geofence
(`locations.lat/lng` exist and are used for the map, never for validation), no
"does this look right?" prompt, no per-worker route to compare against.

The shift is well-formed: valid tag, eligible worker, sane duration. Nothing can catch it.
The **only** reason this report can price it is that the simulation kept the true building
alongside the recorded one; the database has only the recorded one.

Consequence: €732,23 of labour in year one booked to a building nobody cleaned — and because
decision-6 splits the material pot **pro rata by labour hours**, a slice of the €287,80 spend
follows it. At 24 months: **118 shifts, €3 006,13.**

**Fix, in order.**
1. **In-app, worker side** — after a tap, show the building name large enough to read at
   arm's length and give ~60 s of "not this building? undo". Cheapest, catches it at source.
2. **In-app, admin side** — flag a shift whose building is not on that worker's usual round
   (the data to define "usual" already exists in `shifts`). A soft flag, never an accusation.
3. **Help page** — "A shift is on the wrong building" in the admin manual, pointing at
   `PATCH /admin/shifts/:id`, which already accepts `location_id` and is already wired to the
   Correct-a-shift form.
4. **FAQ** — why the panel cannot detect this on its own.

### ▲ 2 — Forgotten tap-out → 8h auto-close (99 shifts) — PROCEDURE EXISTS, THEN EVAPORATES

**What the app says — and it is good, up to a point:**

- Dashboard: *"# shifts were closed by the 8-hour timer and are not paid until they are
  confirmed."* + **Review shifts** (`home.unresolvedSome`, `home.unresolvedLink`)
- Payroll: *"# shift needs confirming before this total is final… the hours below leave it
  out."* + **Confirm them now** (`payroll.caveatUnresolved`)
- Correction form: *"This shift was closed by the 8-hour timer. Saving marks it confirmed and
  puts its hours into payroll — including if you leave the end time exactly as it is."*
  (`shifts.correctUnresolvedNotice`)
- Worker side: `GET /shifts/unresolved` + `POST /shifts/:id/resolve`, and decision-10 locks
  the worker out of clocking in until they resolve it.

That is a complete, well-written procedure. **It stops working at 2000 shifts** for the
reasons in §1.4: the count undercounts, and the link goes to a screen that cannot load the
rows. €1 658,88 in year one, €11 986,40 at 24 months.

**Fix, in order.**
1. **In-app** — count unresolved **server-side**, uncapped. `/admin/data` already returns an
   uncapped `shift_bounds` aggregate for exactly this class of reason; one more scalar
   (`unresolved_total`) costs one indexed count and makes the dashboard number true again.
2. **In-app** — make the shift log's `state=unresolved` filter a **server** filter. It cannot
   be answered from a truncated client-side list, and the honest fix is that the one screen
   whose job is "find the exceptions" must ask the server for them.
3. **Help page** — one page on what the 8-hour timer is, why it exists, and that confirming
   is a payroll act, not an admin chore.
4. **Onboarding video** — 40 s, for the worker, on the resolution screen they will meet on
   their first bad day.

### ▲ 3 — Rate change revalues all history (10 changes, €2 729,42 / year) — DISCLOSED, NO PROCEDURE

`workers.hourly_rate_cents` is **one mutable column**. Every past figure is priced at today's
rate.

**What the app says — three places, and it is honest:**

- `payroll.caveatRateHistory` — *"Known limitation: only one hourly rate per worker is stored,
  so past hours are priced at today's rate. Changing a rate changes what earlier periods
  appear to have cost."*
- `pl.methodRates` — *"Labour is valued at each person's CURRENT hourly rate. There is no rate
  history, so raising a wage changes what every past month appears to have cost."*
- `contracts.noteLabourNoHistory` — *"…This is a known limitation, not something you have
  broken."*
- The API states it back as `labour.rate_basis: "current"` (`server/lib/reporting.js:105-110`),
  and `pl.methodRatesUnknown` exists for the day that value changes.

**What is missing is the number and the procedure.** The disclosure tells the director the
figures move; it never says by how much, and it never says what to do the day they need a
true March cost.

Measured: **app €111 418,23 vs rate-in-force €108 688,81 = €2 729,42 overstated (2,5 %)** over
12 months. It is not spread evenly — it is concentrated in the oldest months, which are
exactly the ones a year-end review looks at:

| month | overstatement | share of that month |
|---|---|---|
| 2025-12 | **€625,99** | ~7 % |
| 2025-11 | €337,29 | ~5 % |
| 2026-05 | −€0,17 | rounding only |

At 24 months: **€8 003,36.**

**Fix, in order.**
1. **Ship decision-30** (`worker_rates` + `worker_rate_changes`). This is already an accepted
   decision record and it supersedes decision-28. It is the fix; everything else is a label
   on a wound.
2. **In-app, until then** — the euro figure cannot be computed without the history, so the
   honest interim is not a number but a **date**: "rate last changed on X" beside each
   payroll line. No column records that today, which is itself the smallest possible piece
   of step 1 and is worth shipping first.
3. **Help page** — "why last March's cost changed" as a named page, because it will be asked.
4. **FAQ** — one line, linked from the payroll caveat.

### ▲ 4 — A tag that worked stops working (1 building, silent from 2026-04) — NO PROCEDURE

**What the app says: nothing that asks this question.** The dashboard's only tag check is
*"has no recorded shift **at all**"* (`web/app/page.tsx:135-140`). A building that produced
**176 shifts** and then produced none is, by that test, healthy. The buildings screen shows a
"last cleaned" month — derived from the same truncated list, so past 2000 shifts it is wrong
for exactly the buildings this matters for.

Consequence: the contract keeps billing, the P&L shows the building as pure margin (revenue,
no labour), and `pl.whyMargin` will cheerfully report an excellent margin. Silence looks like
profit.

The simulation asks the question the panel does not:

```
active buildings with no shift in 21 days:
  Wohnhausanlage Ottakringer 74 — last shift 2026-03-31
```

**Fix, in order.**
1. **In-app** — replace the "never had a shift" triage item with **"has had no shift since X"**,
   thresholded against the building's own contracted frequency (`target_minutes_per_month` is
   already on the row). One SQL `max(start_time)` per building, server-side, uncapped. This
   fixes the false positive of §1.4(iii) in the same change.
2. **In-app** — surface it on the P&L too: a building with revenue and zero labour is not a
   good month, and `pl` already computes both halves.
3. **Help page** — "a building has gone quiet", with the tag re-write procedure. The tag URL
   is already copyable (`locations.copyTag`) and tags are unlocked by decision-15, so the
   remedy is short.
4. **Feature video** — writing a replacement tag, once decision-35 ships in-app tag writing.

### ▲ 5 — A worker never enrols (2 workers) — HALF A PROCEDURE

**What the app says.** If they have **no email**, the dashboard catches it:
*"# active worker has no email address and can never sign in to the app: {names}."*
(`home.noEmailSome`) → **Add their address**. Good.

If they **have** an email and simply never redeemed the code, **nothing fires.** The workers
screen holds the fact — `enrolment_code_redeemed_at` is returned by `WORKER_COLS`
(`server/routes/admin.js:57-59`) and rendered as `workers.codeRedeemed` *"App set up on
{date}"* — but no screen says *"issued three weeks ago, never used"*, and the dashboard's
four triage items do not include it. The director finds out at month end, when a person on
the payroll list has zero hours.

**Fix, in order.**
1. **In-app** — fifth triage item: *"# worker has had an enrolment code for more than 7 days
   and has not set up the app."* Every field needed is already in the payload; this is a
   filter, not an endpoint.
2. **Help page** — the enrolment walkthrough. `workers.codeStandingNote` and `workers.codeOnce`
   are already excellent copy; they just need somewhere to live outside the moment of issue.
3. **Onboarding video** — 30 s of a new cleaner typing the code in, shown to the director so
   they can hand it on.

### ▲ 6 — Hand-entered shift for a dead phone (40 shifts) — GOOD PROCEDURE ✓

**What the app says**, and this one is complete:

- `shifts.createHeading` *"Add a shift by hand"*, `shifts.createIntro` *"For a day that was
  worked but never recorded — a dead phone, or a missing tag."*
- `shifts.createManualNotice` *"…It is paid like any other shift, but it stays marked
  'Entered by hand' in the log below so anyone checking payroll can tell the difference."*
- `shifts.errorEndRequired` *"A shift added by hand must already be finished."*
- Payroll discloses it: `payroll.caveatManual` *"# shifts in this total were entered by hand
  instead of being tapped on a tag. They are paid in full; the tag log has no record of them."*
- It is a derived fact, not a flag: `client_uuid IS NULL` (`web/lib/api.ts:400-403`).

No gap. The one caveat is §1.4: `caveatManual`'s **See which ones** link has the same
dead-end problem as `caveatUnresolved` once the log is truncated.

### ▲ 7 — Worker quits (2) / is dismissed mid-month (1) — PROCEDURE EXISTS, ONE TRAP

**What the app says.** `workers.deactivate`, `workers.statusInactive` *"Inactive — cannot
sign in"*, `workers.codeInactive` *"Inactive — no enrolment code possible"*. Payroll keeps
their rows for the period they worked. Correct.

**The trap.** Resolving an auto-closed shift is normally the **worker's** job
(`POST /shifts/:id/resolve`, `auth: "worker"`, decision-10). A deactivated worker cannot sign
in, so they cannot resolve. The admin route exists and is wired —
`PATCH /admin/shifts/:id` stamps `corrected_at`, and `shifts.correctUnresolvedNotice` spells
out what saving means — so the escape hatch is there. But **nothing connects the two**: the
deactivate button does not say *"this person has 3 unconfirmed shifts you must now confirm
yourself"*, and after deactivation those shifts stay in a queue whose stated owner can no
longer reach it.

**Fix, in order.**
1. **In-app** — on the deactivate confirmation, count their unresolved shifts and link to
   them. One filter over data already loaded.
2. **Help page** — an offboarding checklist: confirm outstanding shifts → deactivate →
   final payroll period.

### ▲ 8 — Contract lost / building dropped (3) and won mid-month (25) — GOOD ✓

Handled correctly and period-correctly. `location_contracts` carries `valid_from` / `valid_to`
(decision-28 — superseded by decision-30 for the *labour* half only; the contract-history half
shipped and stands), revenue is pro-rated over the days of the period
(`analytics.noteTargetSource`), `locations.statusInactive` states the operational consequence
*"Inactive — tapping the tag does not start a shift"*, and the reporting query keeps a
deactivated building visible for any period it was worked in
(`reportableLocations`, `server/lib/reporting.js:182-196`). 44 contract rows for 30 buildings
in the 12-month run — the history is real, not a mutated column.

**Only gap:** nothing tells the director to **collect the tag back** from a building they no
longer clean. Tags are unlocked by decision-15, so a dropped building's tag still resolves.
Fix: one line on the deactivate confirmation, then a help-page offboarding checklist.

### ▲ 9 — Shift crosses midnight (17) / crosses the payroll month (13) — SILENT, CORRECT

No message, and none is needed for correctness: a shift belongs to the period its **start**
falls in, stated identically in `server/routes/admin.js:159-160` and `web/lib/payroll.ts`
(`startsWithin`). The simulation's `--self-check` proves the Vienna boundary arithmetic on
both DST transitions.

**One thing the director cannot see:** a 22:30–01:10 shift on the 31st is paid entirely in the
old month. That is a defensible rule, consistently applied — it is simply never stated
anywhere in the UI. **Fix: a help-page line, nothing more.** This does not warrant in-app copy.

### ▲ 10 — Someone still clocked in (1) — GOOD ✓

`home.onSiteHeading` *"On site right now"*, sorted longest-first, with
`home.overdueFlag` *"over 8 hours, the timer will close this shift"* and
`home.asOf` *"Times read against the clock at {time}."*. Exemplary: it states its own
freshness. No gap.

### ▲ 11 — Material ordered and never priced (7) — DISCLOSED ✓

`materials.costMissing` *"Not priced yet"*; the P&L returns `unpriced_requests` as a first-class
number and refuses to invent a cost from the `inventory_items` price list
(`server/lib/reporting.js:164-181` — *"It is a PRICE LIST, not a purchase ledger"*). Correct
and honest.

**Small gap:** it is not on the dashboard's triage list, so an unpriced order distorts the
P&L until somebody opens the P&L. **Fix: in-app, one more triage item.**

---

### Summary — the gap list, ordered by consequence

| # | event | app's procedure | first fix |
|---|---|---|---|
| 1 | wrong building tapped | **none, and undetectable** — €732/yr, €3 006 at 24 mo | in-app confirm-and-undo after the tap |
| 2 | 8h auto-close at scale | good, then evaporates — €1 659/yr, €11 986 at 24 mo | server-side uncapped count + server-side filter |
| 3 | rate change revalues history | disclosed 3×, no number, no procedure — €2 729/yr | ship decision-30 |
| 4 | tag stops working | **none** — silence reads as profit | "no shift since X" replaces "no shift ever" |
| 5 | worker never enrols (with email) | **none** | 7-day triage item |
| 6 | hand-entered shift | complete ✓ | (fix the truncated link) |
| 7 | worker leaves with unresolved shifts | exists, unlinked | count on the deactivate confirmation |
| 8 | contract won / lost | complete ✓ | tag-return line on deactivate |
| 9 | midnight / month crossing | silent, correct | help page |
| 10 | still clocked in | complete ✓ | — |
| 11 | unpriced material | disclosed ✓ | triage item |

**No item's remedy is a phone number.** Seven of the eleven are answered by copy or a filter
over data the panel already holds.

---

## 3. Which numbers become untrustworthy at scale, and why

| number | where | becomes wrong when | why |
|---|---|---|---|
| "# shifts need confirming" | dashboard | **> 2000 total shifts** (month 9) | filters the LIMITed list; 22 vs 37, then 13 vs 113 |
| shift log for any past month | `/shifts/` | **> 2000 total shifts** | fetches unbounded and filters in the browser; 8 months render empty, then 22 |
| "buildings with no recorded shift" | dashboard | **> 2000 total shifts** | absence from the window ≠ absence from history; flags 2, truth is 1 |
| "last cleaned" per building | `/locations/` | **> 2000 total shifts** | same derived-from-window flaw, and the table is **sorted** by it |
| labour cost per building | `/pl/`, `/analytics/` | **immediately, on any rate change** | one rate column; €2 729/yr, concentrated in the oldest months |
| payroll for a closed month | `/payroll/` | **immediately, on any rate change** | same column; a reprint of March differs from March's printout |
| labour and material per building | `/pl/` | **on any wrong-building tap** | €732/yr misattributed, and decision-6's pro-rata drags materials with it |
| P&L margin flag | `/pl/` | **when a tag dies** | revenue continues, labour stops → the failing building shows the best margin |

Three of these are one bug — deriving an answer about the company from a payload capped at
2000 rows — and one change fixes all three: **any number the panel presents as a count of the
whole must come from a server-side aggregate, not from the row list.** `/admin/data` already
does this correctly for `shift_bounds`, with the reasoning written out at
`server/routes/admin.js:253-257`: *"Without it an empty `shifts` array is ambiguous between
'nobody worked in the period you asked for' and 'the data is gone'."* The same argument
applies to `unresolved`, to `last_shift_per_location`, and to the shift log's filters. The
pattern is established; it is just not applied to the numbers that carry money.

**What did NOT happen:** no query was slow, no connection pool was exhausted, no payload
timed out, and Postgres was never the limiting factor. Nothing here is a performance problem.

---

## 4. Guards, and the proof they fail when removed

The simulation TRUNCATEs and then writes thousands of payroll rows. Two layers, in this order:

**Layer 1 — before any network access** (`assertDemoDatabase`, `demo/db-guard.mjs`, shared
verbatim with `demo/demo-server.mjs` and `demo/make-admin.mjs`). It reads **every** input that
can become the driver's connection target, because `pg` honours a `?host=` query parameter
that **outranks the URL host**, and falls back to `$PGHOST` when the URL names none:

```
$ DATABASE_URL=postgres:///nfc_notdemo                        node demo/simulate.mjs
simulate: refusing database "nfc_notdemo" — demo scripts touch nfc_demo only.

$ DATABASE_URL='postgres://127.0.0.1/nfc_demo?host=timesheets.exe.xyz' node demo/simulate.mjs
simulate: refusing DATABASE_URL ?host=timesheets.exe.xyz — loopback only (it overrides the URL host).

$ DATABASE_URL=postgres:///nfc_demo PGHOST=timesheets.exe.xyz node demo/simulate.mjs
simulate: refusing $PGHOST=timesheets.exe.xyz — loopback only (it becomes the database host).

$ DATABASE_URL=postgres://timesheets.exe.xyz/nfc_demo         node demo/simulate.mjs
simulate: refusing a database on "timesheets.exe.xyz" — loopback only.

$ node demo/simulate.mjs
simulate: DATABASE_URL is not set — refusing to guess.
```

All five are instant and exit non-zero, which is what lets `check-guards.sh` treat *surviving*
as the failure condition rather than hanging on it.

**Layer 2 — after connecting** (`assertLocalServer`). `current_database()` and
`inet_server_addr()` are answered **by the server**, so no connection string can talk them
out of it. The loopback test is the identical inet expression `demo/seed.sql` uses, evaluated
**in Postgres**: a first attempt compared `inet_server_addr()::text` in JavaScript and refused
the loopback it was written to allow, because the text form is `::1/128` and not `::1`.

### The falsification

Six checks were added to `demo/check-guards.sh` (now **22 ok**). Deleting the guard makes four
of them go RED — and the failure messages are the whole point:

```
### MUTATION: delete assertDemoDatabase from demo/simulate.mjs ###
FAIL demo/simulate.mjs refuses a database that is not nfc_demo
       (no refusal: simulate: refusing to touch "nfc_guardcheck_75777" …)
FAIL demo/simulate.mjs refuses a non-loopback database host
       (no refusal: simulate: Error: Connection terminated unexpectedly)
FAIL demo/simulate.mjs refuses a ?host= that overrides the URL host
       (no refusal: simulate: Error: Connection terminated unexpectedly)
FAIL demo/simulate.mjs refuses a non-loopback $PGHOST
       (no refusal: simulate: Error: Connection terminated unexpectedly)
check-guards: 4 FAIL   (exit 1)
```

`Connection terminated unexpectedly` is the finding inside the finding: **with the guard
removed the process had already dialled `timesheets.exe.xyz:5432`** and failed only because
the connection died. A check written as `if cmd; then fail; else ok; fi` would have reported
**ok** for a build that had already left the machine. That is why these three assert the
**refusal message**, not the exit code — the same scar `demo/check-guards.sh` already carries
for `make-admin.mjs`.

### The arithmetic, also falsified

`--self-check` runs 22 assertions with no database: Vienna wall time across both DST
transitions, the payroll month boundary in local time, contract `valid_from`/`valid_to` date
bounds including a leap year, `rateAt`, and the existence of the three routes the load test
measures. Two mutations were run against it:

| mutation | result |
|---|---|
| `rateAt` always returns the latest rate | **RED**, exit 1 |
| `viennaToUtc` assumes a fixed +01:00 | **RED**, exit 1 |
| remove the `bump("fired")` call | **RED** — `assertEventsFired()` throws |

That last one guards this document: every event class in §2 must actually have occurred, or
the run aborts. It has already earned its place — `fired` silently stopped occurring at
`--months 24` when an unrelated resignation moved the headcount under a guard, and the
report would have carried a row about an event that never happened.

---

## 5. Reproducing

```sh
createdb nfc_demo                                             # if it does not exist
DATABASE_URL=postgres:///nfc_demo node server/db/migrate.js
DATABASE_URL=postgres:///nfc_demo node demo/simulate.mjs --json /tmp/sim.json
DATABASE_URL=postgres:///nfc_demo node demo/make-admin.mjs    # to browse the result
sh demo/check-guards.sh                                       # 22 ok
```

`--months 24` reproduces the stress figures. `--seed N` gives a different company; every
finding in §2 and §3 is structural and survives the seed, only the euro amounts move.

`demo/simulate.mjs` TRUNCATEs the same tables `demo/seed.sql` does and deliberately **not**
`admins`, so the demo login survives a re-run. It adds **no dependency** — `pg` via
`server/lib/db.js` and nothing else (decision-16, decision-23).
