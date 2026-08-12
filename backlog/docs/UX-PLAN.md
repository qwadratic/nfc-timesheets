# UX plan — the order the seven specs get built

Written 2026-08-12. Turns `UX-AUDIT.md`, `DESIGN-SYSTEM.md`, `IA-AND-JTBD.md`, `SMS-AUTH.md`,
`ZONES-AND-TAG-WRITING.md`, `MULTI-TENANCY.md`, `JOB-DISPATCH.md` and `ADMIN-ASSISTANT.md`
into one ordered board. **No code was written. Production was not touched.**

Board delta: **24 new tasks, TASK-104 … TASK-127.** Everything else on the board already existed.

| spec | board coverage before | after |
|---|---|---|
| UX-AUDIT (10 findings) | none | 104 105 106 107 108 110 111 112 |
| DESIGN-SYSTEM | none | 106 108 109 |
| IA-AND-JTBD | none | 107 113 114 115 116 117 118 |
| SMS-AUTH / decision-31 | none | 119 120 121 122 123 124 125 126 127 |
| ZONES / dispatch / tenancy / assistant | 78 80 82 84 86 87 89 91 · 69–75 · 76 77 79 81 83 85 88 90 · 92–103 | unchanged |

---

## The first three things to build

```
1  TASK-104   payroll caveat lies about the sign, and the CSV carries none of it
2  TASK-105   P&L Gesamt ≠ sum of its own column
3  TASK-106   globals.css foundation (tokens, --border-strong, overflow-wrap, tfoot labels)
```

**Why these three, in this order.** 104 and 105 are the only two findings where the system
prints a **wrong number about money** and offers no way to notice. 104 is worse than 105:
the payroll screen names a 120 000 € discrepancy, describes its direction incorrectly, hides
the row cap that caused it, and leaves the CSV button enabled — and the CSV is the artefact
the accountant pays from. 105 is a smaller number and stays inside one screen.

106 is third and not first because it is a *floor*, not a fix: it is one CSS commit that four
later tasks stand on, and it cannot be split without two agents editing `globals.css` at once.

Everything else is a screen that is confusing. These three are a screen that is **wrong**.

---

## Order by consequence

```
W1  money is wrong                104 105
W2  the floor                     106            ← blocks 107 108 109
W3  the panel can fail visibly    107 110 111 112
W4  the panel reads right         108 109 114
W5  routes stop lying             115 116 117 113 118
W6  identity that works in a      120 121 122 123 124 125 126
    stairwell (decision-31)
W7  everything else               deliberately not yet — see below
```

W3 is the point where a director could tell you **why the pilot ran once and stopped**.
Today that question is unanswerable: 500s render as an eternal „Wird geladen…" (107), Sentry
is blind twice over (112 + TASK-44), and the map has never had a key in the bundle (111).
⚠ Not a UI opinion — `dashboard-error-500-1280.png`, `systemctl cat nfc-api`,
`grep -rl AIza /srv/nfc/public` → nothing.

---

## Parallel groups

Safe to run at the same time (no shared file):

```
group A   104           web/lib/payroll.ts, payroll/page.tsx     ⚠ + messages/*.json
group B   105           web/lib/pl.ts
group C   111 112       ops/deploy.sh, ops/systemd/nfc-api.service
group D   120           server/lib/phone.js (new file)
group E   127           decision record only
```

Files that **cannot survive concurrent editors** — learned the hard way:

| file | tasks that touch it | rule |
|---|---|---|
| `web/messages/{en,de}.json` | 104 109 110 114 122 | one at a time, always |
| `web/app/globals.css` | 106 (108 109 after) | 106 owns it alone |
| `web/lib/nav.ts` | 115 (116 117 after) | 115 owns it alone |
| `server/routes/admin.js` | 79 80 86 93 98 122 | one at a time |
| `server/lib/auth.js` | 123 90 79 | one at a time |
| page-level TSX on 11 screens | 107 108 110 | serialise; wide + shallow |

Strictly sequential chains:

```
106 → 107 → 113 → 118
106 → 108
106 + 104 → 109
115 → 116
105 + 115 → 117
120 → 121 → 123 → 124 → 125
              ↘ 122        ↘ 126
```

---

## Blocked on the OWNER vs blocked on WORK

**Blocked on the owner** — no agent can start these, and none of them block the first three:

| task | what only you can do | what it actually blocks |
|---|---|---|
| 119 | Twilio console + API key + 5 `psst set` | **only** the live-SMS AC of 123 |
| 76 | buy the operator-owned tag domain | tenant #2, and nothing before it |
| 41 | cut the TestFlight build | every iOS fix reaching a phone |
| 43 | Play Console: privacy URL, data safety, rating | Android distribution |
| 89 | Apple entitlement request (`formats=["TAG"]`) | 91 only |
| 95 | model-provider DPA | assistant in production, not its development |
| 111 (partial) | go-ahead to deploy + run the geocode backfill | the map drawing |

`lib/sms.js` is optional at boot exactly like `SENTRY_DSN` (decision-23's pattern) ∴ the whole
SMS stack 120→124 is buildable and testable with **zero credentials**. Do not wait on 119.

**Blocked on work** — ordinary dependencies, listed in the chains above.

---

## What should NOT be built yet, and the small slice that should

**Dispatch (69–75) — do not build.** `JOB-DISPATCH.md`'s own gate: dispatch pays off at ≥15
workers who don't all know each other, ≥20 jobs/week, jobs arriving when the dispatcher isn't
there. Today **0 of 3**. At 4 workers dispatch is a spreadsheet with extra steps.
→ smallest slice worth doing: **TASK-70, location access instructions.** One text column, the
biggest single cause of a wasted trip, useful at N=4, and it is the only part of dispatch that
does not need a jobs table. Everything else waits, including 71 (push to a closed app), which
is a real prerequisite but for a thing that should not exist yet.

**Multi-tenancy (77–90) — do not build.** Production is 8 shifts / 4 workers / 1 location and
there is no tenant #2. RLS-`FORCE` is the right design *when there is a second tenant*.
→ smallest slice: **TASK-76 only — buy the domain.** It is the one item with a hard deadline
rather than a trigger: per-tenant tag host = per-tenant app release (decision-24 §6), so one
shared host is the only workable answer, and the window shuts the moment tags are on someone
else's walls. decision-15's revisit trigger has already fired. Everything else is priced and
parked.

**Assistant (92–103) — do not enable, but the cage is cheap.** If it is built at all, build
**92 → 93 → 94** and stop: the Postgres GRANT cage, the capability registry, the egress scrub.
Stopping after step 3 risks nothing, because nothing can be talked into anything yet.
**Cut TASK-103 first** — it is the only one where the model *creates* data, and „um 6" read as
06:00 when the worker meant 18:00 is plausible, silent, and lands on a payslip.

**Zones (78–84) — after the pilot repeats, not before.** Zones are cheap and the design is
sound (a `locations` row with `parent_id`, 0 lines of parser change, 0 rows migrated). But
m²/h has *nothing calibrated it*: n=5 and the 3× median cut-off are invented numbers against
8 shifts. Build zones when there is a second month of taps to test them against.
→ the exception: **tag writing (86, 87)** serves a real field job today — „did the tap land"
and „this tag is dead, write a new one in the stairwell". Android first; iOS entitlement in a
build of its own (89) carrying **no feature**, because the same key already failed once and a
build that will not upload blocks *every* iOS fix.

---

## Things this plan found that were not in any spec

**Migration number collision.** Three designs each wrote „migration 006": phone identity
(decision-31), zones (decision-33), tenancy (decision-32). Allocation, by planned ship order,
now recorded as a comment on all three tasks:

```
006 = phone identity (TASK-121)   007 = zones (TASK-78)   008 = tenancy (TASK-77)
```
Never run two of them in parallel against one database. `migrate.js` runs `psql -1` ∴ no
`BEGIN/COMMIT` in the file.

**TASK-44 was half a fix.** Setting `SENTRY_DSN` still yields zero traces while the installed
unit runs `node server.js` without `--import ./instrument.mjs`. An AC pointing at TASK-112 was
added; 44 is not done until 112 is.

**The real bug behind finding 5 is not the flag.** It is that a unit file in git and a unit
file on the VM are allowed to differ silently. TASK-112 fixes the general case.

---

## Standing rules every one of these tasks inherits

- Money is **integer cents** end to end, time is **integer minutes**, Vienna is `Europe/Vienna`.
- German (Austrian business German) is default; `en.json`/`de.json` keep **exact** key parity;
  no bare JSX literal.
- decision-29: the panel works on a phone. Tables → labelled cards below 768px.
- Accessibility is never traded for visual polish. `--border-strong` (TASK-106) exists because
  an input's only boundary is currently **1.38:1** — a WCAG 1.4.11 failure, not a preference.
- Dependency budget: server = `pg` + `@sentry/node`. Web adds no npm dependency without a
  decision record.
- **Never** edit `NFCTimeSheets/NFCTimeSheets.xcodeproj/project.pbxproj`.
- Production is **read-only** for every agent. Demo work uses `nfc_demo`, guarded by
  `demo/check-guards.sh`.
- **A check whose negative case cannot fail is not a check.** Every task above carries the
  mutation that must turn it RED, and the RED output goes in the task notes. This project has
  been bitten three times: a hung Chrome, a hung demo server, and `data-label`s that existed
  but were wrong.

⚠ Nothing in `DESIGN-SYSTEM.md` has ever been rendered. The contrast ratios are computed and
the column widths come from the audit — no rebuilt bundle has been observed. TASK-106 is where
that stops being true.
