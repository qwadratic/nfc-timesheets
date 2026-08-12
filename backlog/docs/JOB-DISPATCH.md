# Job dispatch — "Uber for cleaning"

Product + operational design. **No implementation.** Written 2026-08-13, Vienna.

---

## Verdict first

**Do not build dispatch. Build work orders.**

At 4 workers / 1 location / 8 shifts ever recorded, a dispatch system is a spreadsheet with
extra steps and a worse phone. The director can hold the entire roster in their head and
assign by WhatsApp in 30 seconds. No ranking algorithm beats that, and every one of them is
worse when trained on 8 rows.

It stops being true when **all three** are true at once:

| gate | threshold | why that number |
|---|---|---|
| roster too big to rank mentally | **≥15 active workers** | below this the director's ranking is better than any score, and the workers all know each other → price collusion is one group chat |
| enough jobs to repay software | **≥20 dispatchable jobs/week** | below this total dispatch effort is <1 h/week. Nothing repays that. |
| jobs arrive when the dispatcher does not exist | out-of-hours, or **>1 dispatcher** | a single available human is the cheapest dispatcher ever built |

Any **two of three** → build the work-order half (assign, accept, arrive, done). Not the
dispatch half (rank, price, escalate).

Today: 0 of 3. ∴ everything below §9 is design-for-later, deliberately.

The one thing this product genuinely has that a generic dispatch app does not: **the NFC tap
at the door is already proof of arrival.** "Did they actually show up" is the hard problem in
every dispatch system, and it is solved here as a side effect of the thing that already ships.
Build around that asset; do not rebuild it.

---

## 1. The job model

### 1.1 Shape

```
job
  id                uuid
  location_id       uuid   -> locations(id)      REQUIRED   (decision-21: uuid, never slug)
  job_type          text   closed vocabulary     REQUIRED
  complexity        text   simple|standard|hard  REQUIRED
  est_minutes       int    integer minutes       REQUIRED   + est_source
  est_source        text   template|admin        REQUIRED   (never "guessed by code")
  window_start_at   timestamptz                  REQUIRED   Europe/Vienna semantics
  window_end_at     timestamptz                  REQUIRED   deadline is a WINDOW, not a point
  urgency           text   normal|urgent         REQUIRED
  required_items    (job_id, inventory_item_id, qty)  0..n  REQUIRED to be RESOLVED (may be empty)
  access_note       text                         REQUIRED   how do you physically get in
  billable          bool + client_id             REQUIRED   who pays: client, or internal cost
  price_floor_cents int                          REQUIRED   see §3
  authorised_by     admin id                     REQUIRED
  status            see 1.3
  source_ref        text   the issue that produced it (free text, kept verbatim)
```

Money integer cents. Time integer minutes. Vienna is `Europe/Vienna`. No floats anywhere —
a job price is a subtraction, not a rounding argument.

**`complexity` is not a synonym for duration.** Duration is minutes. Complexity is *can this go
wrong* — it drives who is eligible (§2) and whether a second person is needed, not the price
directly. Keeping them separate stops "hard" being used to smuggle a price rise.

### 1.2 Qualification — the gate that keeps the system honest

> A badly qualified job poisons a dispatch system. Every field in §1.1 marked REQUIRED is
> `NOT NULL` **before a job may enter the feed.** No exceptions, no defaults, no "the worker
> will figure it out".

The premise says an upstream service captures, validates and enriches issues. Treat that
output as **input, not truth**. It lands in `draft` and a human qualifies it.

Rule inherited verbatim from `material_requests` (005_v2_features.sql:29–32):

> *free text is the input and it stays free text until a human maps it. There is no fuzzy
> match against inventory_items, no auto-approval and no automatic status advance.*

Dispatch must not become a back door around that rule. An enrichment service that guesses
"der blaue Reiniger, der große" → `inventory_item_id = 7` is putting a wrong number into a
P&L with nobody able to see why. Same failure, bigger blast radius, because now it also sends
a person across Vienna.

**Qualification checklist — a human ticks these, or the job stays in `draft`:**

1. Which building, as a UUID. Not a name, not an address string.
2. What is actually wrong, in one sentence a cleaner can act on.
3. **How do you get in.** Key, code, concierge (with hours), tag at the door, "ring Frau K.".
   ← this is the single largest cause of a wasted trip and it is the field most often skipped
4. What do you need to bring. Resolved to `inventory_item_id` + qty by the human, or empty.
5. How long, and where the number came from (a template median, or a named admin's guess).
6. By when — a window, in Vienna time.
7. Who pays.
8. Does the price floor compute (§3). If not, the job cannot be offered.

**Un-qualifiable is a legitimate outcome.** `draft → rejected` with a reason, terminal. A
system with no reject path grows a permanent silt layer of half-jobs.

**Qualification latency is itself a metric.** Oldest `draft` age goes on the health screen
(§7). A job qualified 20 minutes before its deadline was never dispatchable.

### 1.3 States

```
draft ──qualify──> qualified ──offer──> offered ──accept──> accepted
  │                    │                   │                   │
  │                    │              (no accept)         NFC tap at door
  │                    │                   ↓                   ↓
  └──reject──> rejected└──cancel──> cancelled  ──> unfilled  started ──> done ──verify──> verified
                                                       │                   │
                                                       └──────> escalated  └──> failed (reason req.)
terminal: verified · cancelled · rejected · failed
side state: blocked_materials  (leaves the feed, §5)
```

- `started` is set by the **existing NFC tap**, not by a button. A self-declared arrival is a
  claim; a tap at the door is evidence.
- `unfilled` is a real, visible, non-shameful outcome. It is **not** hidden behind a retry loop.
  A dispatch system whose UI cannot say "nobody took this" will lie to you instead.
- No `en_route` state. `ponytail:` it is unverifiable self-report and would need live location
  tracking to mean anything — which is a GDPR decision, not a feature toggle. Upgrade path if
  ever needed: a decision record first, then a coarse "left for the job" tap, never background GPS.

---

## 2. Assignment

### 2.1 Ranked offer, never broadcast

Broadcast-to-all is the obvious design and it is wrong:

- it selects the **fastest thumb**, not the best-suited worker
- every job produces n−1 losers → workers learn the feed is a lottery → they stop opening it
- it makes the price ladder meaningless: everyone sees every price

Ranked exclusive offer, in waves.

### 2.2 Hard filters (eligibility) — a fail here removes the worker, full stop

| filter | rule | today |
|---|---|---|
| active | `workers.active = true` | ✓ exists |
| not double-booked | no open shift, no other `accepted` job overlapping the window | ✓ server is authoritative for open shifts (decision-19) |
| skill | job_type ∈ worker's skills | ✗ **no skills column exists** |
| rest period | ≥11 h since last clock-out (AZG §12) | ✗ computable from `shifts`, not implemented |
| daily/weekly cap | ≤12 h/day, ≤60 h/week (AZG §9) | ✗ same |
| urgent consent | job urgent ⇒ `urgent_ok` true **and** inside the worker's declared hours | ✗ |

⚠ **The AZG/Kollektivvertrag rows are a layman's reading, not legal advice.** Offering a job
6 hours after clock-out is not "a bad suggestion", it is an employer instructing an illegal
shift. Before any automated offer goes out, the hour rules and the
*Kollektivvertrag Denkmal-, Fassaden- und Gebäudereinigung* overtime supplements must be
checked by someone qualified. Do not ship the filter on an agent's reading of a statute.

### 2.3 Soft score (ordering) — only ever reorders eligible workers

```
score = w1·proximity + w2·materials_in_hand + w3·(1 − load_today) + w4·reliability
```

- **proximity** — needs geocoded locations. Today `locations.lat` is NULL on the one production
  row (TASK-16). Until then proximity is a manual zone tag, or it is nothing. Do not fake it
  with address-string similarity.
- **materials_in_hand** — self-reported (§5), so it is a *soft* input, not a hard filter. A
  worker who has the mop is worth ranking up; a worker who says they do not is not disqualified,
  they just cost a supply run.
- **load_today** — minutes already worked, from `shifts`. Fairness input, not just capacity:
  without it the same three reliable people get every job until they quit.
- **reliability** — acceptance rate + on-time arrival. **Gated: needs ≥20 completed jobs per
  worker before it enters the score at all.** A reliability score built from 3 data points is a
  coin flip that reduces a real person's income.

`w1..w4` are configuration, visible to the director, published to workers. A scoring function
nobody can inspect is a grievance generator.

### 2.4 Waves and the "nobody accepts" path

| wave | who | exclusive window | price |
|---|---|---|---|
| 1 | top-ranked eligible worker | urgent **90 s** · normal **10 min** | floor + step 0 |
| 2 | next 3 by score | urgent **3 min** · normal **20 min** | step 1 |
| 3 | all remaining eligible | urgent **5 min** · normal **30 min** | step 2 (= ceiling) |
| 4 | **a human** | — | — |

**The ladder always ends at a human. There is no auto-assign.** Assigning a job to a worker who
did not accept it produces a no-show, which is strictly worse than an unfilled job: you have
now also lost the information that nobody was available.

At wave 4 the director sees the job at the top of the health screen with: every decline and its
reason, who never responded, the current price, and three buttons — *assign by hand*, *push the
window*, *tell the client it slips*. **The system never messages the client automatically.**

Non-response ≠ decline. Both move the offer on; only an explicit decline carries a reason, and
only non-response degrades the responsiveness metric (§4).

---

## 3. Pricing

### 3.1 The floor — hard invariant

> **A job never pays below the worker's own hourly rate for the time it takes, travel included.**

```
floor_cents = ceil((work_minutes + travel_minutes) × rate_cents_per_hour / 60)
```

`rate_cents_per_hour` is resolved from **`worker_rates` on the job's Vienna calendar date**
(decision-30) — the same source payroll and the reports use. Rounding is **up**, once, at the
end: the worker is never short by a cent through arithmetic.

🔒 **This is un-computable today and that blocks all of §3.** `workers.hourly_rate_cents` is a
single mutable column; `worker_rates` does not exist (TASK-55). Price a job in March at "today's
rate", give a raise in September, and March's job price silently changes — decision-30's bug,
now attached to a number someone was *paid*. **decision-30 / TASK-55 is a hard prerequisite for
any pricing.**

### 3.2 The ladder — fixed published steps, two ceilings

```
price(step) = clamp( round(floor × STEP[step]),  low = floor,
                     high = min( floor × MAX_MULT , billable_ceiling ) )

STEP      = [1.00, 1.25, 1.50]      published, fixed, not per-worker
MAX_MULT  = 1.8                      published
billable_ceiling = what the client pays for this job − target margin
```

Two ceilings, take the minimum. When `billable_ceiling` bites, **the margin absorbs it, never
the worker** — the clamp's lower bound is the floor, so a thin-margin job goes to zero or
negative margin and gets flagged, rather than underpaying a person.

Worker pay rising must **never** silently raise the client's invoice. Different contract,
different consent, different decision record.

### 3.3 Gaming — stated honestly

**A worker declining until the price rises is rational and you cannot forbid it.** You can only
make it a bad bet.

| defence | mechanism | honest limit |
|---|---|---|
| declining costs your place | the step belongs to the **job**, not the person. Decline at step 0 and you see step 1 only after everyone else has → higher price, much lower probability | only works with enough workers that "everyone else" is a real set. **Dead at N=4.** |
| low ceiling | 1.8× max, 2 steps. Expected value of holding out is small | tune it too low and the ladder never fills anything; too high and holding out pays |
| acceptance rate feeds ranking | declining costs future offers, and this is **published** | needs history (≥20 jobs/worker) before it is fair to apply |
| blind escalation | the worker sees the current price and that a bounded ceiling exists, not the next step | ⚠ **workers talk. They will know the ladder within a month.** Do not rely on this. It buys weeks, not a defence. |
| the floor | declining never gets a worker below-cost work, so holding out is a greed strategy, not a survival one | — |

**The one you cannot design against: collusion.** Four cleaners in one group chat can all
decline to step 2 on every job, forever, and no algorithm distinguishes that from a genuinely
busy Tuesday. Mitigations are non-algorithmic: a bounded ceiling caps the damage, and the health
screen surfaces "declined at step 0 by all eligible" as a pattern for a human to notice. **At
small N, dynamic pricing is theatre.** It is one of the strongest reasons to defer §3 entirely.

**Explicitly rejected: surge multipliers keyed on demand/time-of-day.** They invite exactly the
gaming above, they are unexplainable to the person receiving the money, and they turn a pay
dispute into an argument about an algorithm. Fixed published steps or nothing.

### 3.4 The invariants, as a runnable check

Not pseudocode — this runs, and it was mutation-tested (both mutations below go RED):

```js
export function floorCents(workMin, travelMin, rateCentsPerHour) {
  if (!Number.isInteger(workMin) || workMin <= 0) throw new RangeError("workMin");
  if (!Number.isInteger(travelMin) || travelMin < 0) throw new RangeError("travelMin");
  if (!Number.isInteger(rateCentsPerHour) || rateCentsPerHour <= 0) throw new RangeError("rate");
  return Math.ceil(((workMin + travelMin) * rateCentsPerHour) / 60);   // UP, once, at the end
}

export function ladderCents(floor, step, { maxMult = 1.8, billableCeiling = Infinity } = {}) {
  const STEPS = [1.0, 1.25, 1.5];
  const mult = STEPS[Math.min(step, STEPS.length - 1)];
  const ceiling = Math.min(Math.floor(floor * maxMult), billableCeiling);
  return Math.max(floor, Math.min(Math.round(floor * mult), ceiling));
}

const f = floorCents(45, 15, 1500);                       // 60 min @ €15.00/h
assert.equal(f, 1500);
assert.equal(floorCents(7, 0, 1300), 152);                // 151.66 -> 152, never 151
for (let s = 0; s < 6; s++) assert.ok(ladderCents(f, s) >= f);                    // never below floor
for (let s = 0; s < 6; s++) assert.ok(ladderCents(f, s) <= Math.floor(f * 1.8));  // bounded
assert.equal(ladderCents(f, 5, { billableCeiling: 900 }), f);   // margin loss, NOT worker loss
```

| mutation | result |
|---|---|
| `Math.ceil` → `Math.floor` in the floor | ✗ RED — `151 !== 152` |
| drop the `Math.max(floor, …)` lower clamp | ✗ RED — billable ceiling underpays the worker |

Both fail. The check can fail ∴ it is a check.

---

## 4. Reliability — the escalation ladder

Presence is **derived, not declared**: `online = app foregrounded OR shift open` within the last
15 min. A manual "I'm available" toggle rots — nobody ever turns it off, and then the roster
lies. `ponytail:` derive it; the only manual flag is `urgent_ok`, because that is a *preference*
with a schedule ("never before 06:00"), not a state.

### 4.1 The ladder, with timings and audience

`D` = `window_start_at`.

| when | condition | worker sees | director sees | client |
|---|---|---|---|---|
| offer sent | — | push, price, window, materials, access note | job in "offered" | — |
| +90 s urgent / +10 min normal | no ack | offer silently withdrawn | wave advances | — |
| on accept | — | job in "my jobs today", calendar entry | job locked to a name | — |
| **D − 60 min** | not started | "Still on for Neuhaus at 14:00?" one-tap confirm | — | — |
| **D − 30 min** | no confirm | second nudge, different channel if available | job turns **amber** | — |
| **D + 15 min** | no NFC tap at door | "Running late / cannot make it?" | **amber**, worker name + phone one tap away | — |
| **D + 30 min** | still no tap | job reopens; worker told plainly it was reopened | **red**, top of the screen | — |
| **D + 45 min** | still unfilled | — | **red + a decision prompt**: reassign / push window / notify client | only if the director presses the button |

Nothing in this ladder messages the client automatically. Ever. Who tells a client their
stairwell will not be cleaned today is a relationship decision.

### 4.2 No-show marks are reviewed by a human before they count

A missed tap can be: phone died, U-Bahn stopped, wrong key, tag adopted by another app
(this actually happened, 2026-08-11), or an actual no-show. A `no_show` mark is created in
`pending_review`, and it **does not affect ranking or pay until an admin confirms it**.

Automatic reputation damage from an unreviewed signal is how these systems become abusive, and
this one already knows its own signals are unreliable.

### 4.3 🔒 The blocking prerequisite nobody has built

Every row above needs the server to reach a phone **with the app closed**. Today:

| channel | state |
|---|---|
| APNs (iOS) | ✗ not set up — `docs/apns-setup.md` does not exist (TASK-26) |
| FCM (Android) | ✗ not set up; the ongoing notification is local, not server-pushed |
| local notification | ✓ works, but is scheduled *at clock-in* — useless for a job that arrives later |
| SMS via Twilio | ⚠ exists for OTP (decision-31), ~€0.075/msg, `SMS_DAILY_CAP` default 200. A dispatch ladder is ~4 messages per job. |

**No push → dispatch is a phone call → dispatch is a spreadsheet.** This is prerequisite #1 and
it is not started.

---

## 5. Materials

A job that needs materials the worker does not have is a wasted trip — the same wasted trip that
a missing `access_note` causes, and the second most common one.

### 5.1 What exists, and what does not

- ✓ `inventory_items` — a catalogue (name, kind, unit_cost_cents)
- ✓ `material_requests` — the request lifecycle, `submitted → approved → ordered → arrived`,
  `rejected` terminal, transitions enforced as an explicit table in `routes/admin.js`
- ✗ **who is holding what.** There is no per-worker stock ledger anywhere in the schema.

### 5.2 Self-report, not a ledger

`ponytail:` **do not build per-worker inventory.** At accept time, one screen:

> Für diesen Auftrag brauchen Sie: **Wischmopp**, **pH-neutraler Reiniger**.
> Haben Sie das dabei?  [ Ja ]  [ Nein ]

Cost of being wrong: one wasted trip. Cost of a stock ledger: a second inventory system that
needs someone whose job is stock, and that is wrong within a week of nobody updating it.

Upgrade path, gated: build the ledger only when measured wasted trips (§7) cost more than its
upkeep — rough gate **>5 wasted trips/month** or **>€2 000/month materials spend**.

### 5.3 "Nein" → the existing lifecycle, no new one

```
worker taps Nein
  → job.status = blocked_materials        (leaves the feed; it is not unfilled, it is blocked)
  → INSERT material_requests
       worker_id  = the accepting worker
       location_id = job.location_id       (context only — NEVER a cost split, see below)
       body       = prefilled from the job's required_items, EDITABLE by the worker
       status     = 'submitted'            ← and nothing advances it automatically
  → link row: job_material_requests(job_id, material_request_id)
```

Then, strictly:

| request reaches | job does |
|---|---|
| `approved` | nothing. Approved is not arrived. |
| `ordered` | nothing. The director sees an ETA next to the blocked job. |
| `arrived` | job returns to `qualified` and re-enters the feed **at its original price step** |
| `rejected` | job goes to a **human**, never silently dropped or auto-cancelled |

⚠ **Dispatch must not auto-advance a material request.** 005 forbids automatic status advance
and fuzzy matching against `inventory_items` on purpose. A dispatch feature that "helpfully"
marks a request `arrived` because a worker started the job is overturning that rule without a
decision record.

⚠ **Cost attribution is unchanged: pro-rata by labour hours (decision-6).** A dispatch job must
not charge `cost_cents` to its `location_id`. That is option B — "worker assigns to building" —
which decision-6 explicitly rejected. Anything that starts doing it needs a new decision first.

---

## 6. Incidents and feedback

### 6.1 Any human can report

| reporter | how they get in | what they may attach |
|---|---|---|
| worker | in-app, from a job or standalone (TASK-47) | job_id, shift_id, location_id |
| admin / director | admin panel | anything |
| client contact | tokened link from the existing client portal (`routes/portal.js`) | location_id only |

**Identity comes from the session, never the request body** — the same rule as decision-22 /
decision-31. A reporter field a client can set is a reporter field a client can forge.

### 6.2 What is logged

```
incident
  id, created_at, reporter_id, reporter_role   ← from the session
  severity      S1 worker cannot clock in/out or hours are lost
                S2 director cannot run payroll
                S3 cosmetic / annoyance                     (severities per TASK-64)
  body          free text, the reporter's own words, verbatim, never rewritten
  job_id / shift_id / location_id   optional links
  status        open -> acknowledged -> resolved | wont_fix   (each change: actor + timestamp)
  internal_note admin-only column, separate from body
```

Explicitly **not** logged in v1: photos (a PII grenade with storage, moderation and retention
attached), background location, device contact lists. Add photos only with a decision record
that answers retention and who can see them.

### 6.3 Who can see what

| | body | internal_note | reporter identity |
|---|---|---|---|
| director / admin | all | all | all |
| worker | their own | — | their own |
| client contact | only incidents they filed, status only | — | — |

The `internal_note` field must be **visibly labelled as internal in the UI**. A field that looks
private but is not is how a director's blunt note about a worker ends up in a subject access
request.

### 6.4 Retention — a proposal, not legal advice

⚠ **These numbers need the DPO/lawyer sign-off tracked in TASK-61. Do not ship an agent's
invented retention periods as if they were legal advice.** Recorded here so the conversation
has a starting point.

| data | proposed | rationale |
|---|---|---|
| payroll-adjacent (job price paid, minutes) | **7 years** | BAO §132 Aufbewahrungspflicht |
| incident record + status history | **3 years** | Austrian general civil claim period |
| incident free-text **body** | **3 years, then pseudonymised**, counts retained | bodies will contain names, addresses and complaints about identified colleagues — this is the highest-risk column in the design |
| dispatch offer log (who was offered what, at what price, declined why) | **12 months** | long enough to defend a pay dispute, not longer |
| derived presence/online samples | **30 days** | it is a whereabouts trace of an employee. Keep it short or do not keep it. |

Erasure: today `deleteWorker` is `UPDATE workers SET active=false` and the name persists forever
(TASK-61). Dispatch **adds** personal data — offers, declines, no-show marks, incident bodies —
to a system that has no erasure path. Do not add the data before the path exists.

---

## 7. Observability — one screen for the director

Phone-legible, ~1080 px, no horizontal scroll (decision-29). One question: **do I need to do
something in the next hour?**

```
┌──────────────────────────────────────────────┐
│  DISPATCH   ● GRÜN            Di 13.08 09:41 │   green iff  unfilled=0
│                                              │             AND past_deadline=0
├───────────┬───────────┬──────────┬───────────┤             AND oldest_draft < 4h
│ ANGEBOTEN │ VERGEBEN  │  OFFEN   │ ÜBERFÄLLIG│   otherwise RED, with the reason
│    14     │    12     │    2     │     1     │   ← the only 4 numbers that matter today
├───────────┴───────────┴──────────┴───────────┤
│ Zeit bis Annahme (Median)          4 min 20s │
│ Nicht qualifiziert (ältester)      3   1h12m │   ← draft backlog + age
├──────────────────────────────────────────────┤
│ Vergeben in Welle   1▓▓▓▓▓▓▓▓ 2▓▓▓ 3▓ Eskal ▏│   ← mostly wave 3? ranking is wrong
│ Preisstufe          Basis▓▓▓▓▓▓ +25%▓▓ +50%▏ │   ← mostly ceiling? the floor is too low
│ Absagegründe   Material 4 · Zeit 3 · Weg 2   │   ← always "Weg"? your zones are wrong
├──────────────────────────────────────────────┤
│ GEFÄHRDET — sortiert nach Frist              │
│ 🔴 Neuhaus 3 · M. Kovač · kein Tap · +22 min │   → tap = call / reassign / notify
│ 🟠 Wiedner 12 · unbesetzt · Frist in 35 min  │
│ 🟠 Lange G. 7 · blockiert: Material bestellt │
└──────────────────────────────────────────────┘
```

Design rules for this screen:

- **One boolean at the top, and it must be able to be red.** A dashboard that is always green is
  a decoration. Green has exactly one definition and it is printed next to it.
- **Every distribution answers a specific "your system is misconfigured" question** — named in
  the comments above. A chart with no such question is a chart nobody reads.
- **No vanity metrics.** No cumulative jobs ever, no total revenue. Those belong in analytics,
  not in a health screen.
- **Every at-risk row has exactly one action.** If the director has to navigate away to act, they
  will use the phone in their other hand instead, and the screen becomes a museum.

---

## 8. Prerequisites already on the board

| needed for | repo state |
|---|---|
| push to a closed app | ✗ TASK-26, not started. **Blocks everything in §4.** |
| price floor from a rate history | ✗ TASK-55 / decision-30. **Blocks all of §3.** |
| geocoded locations for proximity | ✗ TASK-16 — `locations.lat` is NULL in production |
| worker skills, zones | ✗ no column exists anywhere |
| feedback channel | ✗ TASK-47 |
| incident process + severities | ✗ TASK-64 |
| erasure path + retention | ✗ TASK-61 |
| arrival proof | ✓ **already shipped** — the NFC tap |
| material lifecycle | ✓ already shipped — `material_requests` |
| responsive admin | ✓ decision-29 |

Seven of ten are missing, and two of them are hard blocks. That is the real state of "the largest
and least-defined piece".

---

## 9. If there were one week

**Build work orders. Do not build dispatch.**

| in | out |
|---|---|
| `jobs` table with the §1.1 fields, `NOT NULL` enforced | pricing of any kind |
| admin creates a job and **assigns it to one named worker** | ranking, scoring, waves |
| worker sees "meine Aufträge heute", accepts or declines with a reason | escalation ladder, timers |
| the existing NFC tap flips `accepted → started` | presence, online state |
| `access_note` on the job (and on the location, reused) | reliability scores |
| materials: the yes/no question, `Nein` → a `material_requests` row | per-worker stock |
| one list on the admin panel: today's jobs, colour by state | the health screen of §7 |

That is a **work-order system**, and it is genuinely useful at 4 workers today. It is also the
exact substrate dispatch needs later: the `jobs` table, the qualification discipline, and the
tap-as-arrival link are unchanged when ranking and pricing arrive on top.

The test any week-one scope should pass: *useful immediately, and not thrown away later.* This
passes. A ranking algorithm at N=4 fails both halves.

Second call, if the week has slack: **push to a closed app** (TASK-26). It is the prerequisite
for dispatch, and it independently improves the 8 h warning, incidents and the missed-shift
nudge. Nothing else on this list has that leverage.

## 10. What I refuse to build, and the gate that unlocks it

| refuse | until |
|---|---|
| price discovery / escalation ladder | ≥15 workers **who do not all know each other**, ≥20 jobs/week, **and** `worker_rates` shipped |
| automatic ranking / reliability score | ≥200 completed jobs **and** ≥20 per worker |
| surge or demand multipliers | **never.** Fixed published steps or nothing (§3.3) |
| per-worker material ledger | >5 measured wasted trips/month, or >€2 000/month materials |
| worker-to-worker job swaps | ≥15 workers. Below that a swap is a phone call and always will be |
| background location / live ETA | a decision record that answers GDPR first. Not a feature toggle |
| client-created jobs entering the feed directly | **never.** Client input is unqualified by construction; it lands in `draft` and a human qualifies it. This one is not a scale gate. |

## 11. What I could not settle

1. **Whether any "issue" stream exists.** The premise assumes a service that captures, validates
   and enriches issues. Nothing in this repo does that, and its output shape is the single
   biggest unknown in §1.2. If it emits free text, §1.2 is most of the work. If it emits
   structured rows, most of §1.2 evaporates. **Asked, not assumed.**
2. **Travel time.** The floor includes it and nothing can compute it — no geocoding, no routing.
   A flat 15 min per job is the honest placeholder and it will be wrong across Vienna.
3. **Whether these jobs are billable at all.** §1.1 assumes some are extra-contractual client
   work and some are internal cost. That is a commercial question and it changes `billable_ceiling`
   in §3.2 completely.
4. **Employment status.** This design assumes employees on a Kollektivvertrag, priced above a
   floor. If the intent is contractors bidding, that is a different legal object entirely
   (Scheinselbständigkeit) and none of §3 survives contact with it.
