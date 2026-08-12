# Agent Fleet Plan — m-5 Vienna Pilot

**Written** 2026-08-12 · **Baseline** `75834a2` · **Branch** `plan/agent-fleet-2026-08-12`
**Target** the exit criteria in `backlog/milestones/m-5 - vienna-pilot.md`
**Status** PLANNED, NOT STARTED. Nothing below has run.

---

## The one thing that makes this parallelisable

Eight lanes editing this repo at once would collide in exactly four places. Three are cheap to
pre-empt and one is not:

| Hot spot | Why it collides | Pre-emption |
|---|---|---|
| `server/check-api.js` | 3375 lines, **every** lane wants to append assertions | Phase 0 splits it: new assertions go to `server/checks/<feature>.check.js`, registered in an append-only `ops/check-all.sh` manifest. A merge conflict becomes one added line. |
| `server/db/migrations/` | two lanes both writing `006_*.sql` collide unrecoverably | Numbers are **reserved in Phase 0** and no lane may choose its own |
| `ops/systemd/` | backup work and alerting work both edit the same units | Both assigned to **one lane** (OPS), not two |
| `server/routes/admin.js` | 61.6 KB touched by money, metrics and transactions work | **Not preventable.** Handled by merge ordering instead — see Phase 2. |

This is the whole design. Without Phase 0, eight parallel lanes produce eight conflicting
edits to one file and the merge costs more than the work did.

---

## The graph

```
                          ┌─────────────────────────────────┐
   PHASE 0 · FOUNDATION   │ 1 agent · serial · main worktree│  BLOCKING
   ~1h agent              │ F1 check-harness split          │
                          │ F2 skip-fails-under-CI          │
                          │ F3 db-guard port                │
                          │ F4 migration numbers reserved   │
                          └────────────────┬────────────────┘
                                           │ foundation.contract.json
        ┌──────────┬──────────┬────────────┼───────────┬──────────┬─────────┐
        ▼          ▼          ▼            ▼           ▼          ▼         ▼
   PHASE 1 · FAN-OUT · 8 worktrees · fully parallel · each emits lane-result.json

    ┌───────┐ ┌───────┐ ┌─────────┐ ┌──────┐ ┌───────┐ ┌─────────┐ ┌────┐ ┌─────┐
    │  PM   │ │ FIELD │ │   OPS   │ │  CI  │ │  SEC  │ │ METRICS │ │VOICE│ │MONEY│
    │ 63,64 │ │  49   │ │  57,62  │ │56,66 │ │  54   │ │   58    │ │ 47 │ │ 55  │
    │  65   │ │       │ │         │ │      │ │       │ │         │ │    │ │     │
    │ docs  │ │research│ │  ops    │ │ CI   │ │security│ │ schema  │ │x-plat│ │MONEY│
    │ ~2h   │ │  ~1h  │ │  ~3h    │ │ ~3h  │ │ ~2h   │ │  ~4h    │ │ ~6h │ │~10h │
    └───┬───┘ └───┬───┘ └────┬────┘ └──┬───┘ └───┬───┘ └────┬────┘ └──┬─┘ └──┬──┘
        │         │          │         │         │          │         │      │
        └─────────┴──────────┴─────────┴─────────┴──────────┴─────────┴──────┘
                                           │ merge in ascending collision order
                                           ▼
                          ┌─────────────────────────────────┐
   PHASE 2 · INTEGRATION  │ serial · main worktree          │
   ~3h                    │ merge PM→FIELD→OPS→CI→SEC→      │
                          │       METRICS→VOICE→MONEY       │
                          │ then task-59 (needs the         │
                          │ withTransaction helper MONEY    │
                          │ introduces)                     │
                          └────────────────┬────────────────┘
                                           │ integration.json
                                           ▼
                          ┌─────────────────────────────────┐
   PHASE 3 · MOBILE       │ task-40 plurals → task-41 TF    │
   ~2h agent              │ task-42 Android hardware        │  ⚠ HUMAN GATE
   + days of human/store  │ both carry the new key from SEC │
                          └────────────────┬────────────────┘
                                           ▼
                          ┌─────────────────────────────────┐
   PHASE 4 · GATE         │ decision-compliance agent       │
   ~2h                    │ demo-verification agent         │
                          │ (must differ from each builder) │
                          └────────────────┬────────────────┘
                                           │ gate-verdict.json + handoff memo
                                           ▼
                                       HUMAN REVIEW
```

**Critical path:** Phase 0 → MONEY → task-59 → gate. MONEY is the long pole at roughly 10 agent
hours; the other seven lanes finish inside its shadow. Wall clock is therefore about
`1 + 10 + 3 + 2 ≈ 16 agent hours`, versus roughly 34 if run serially. The parallelism is worth
about 2.1x — not 8x, because one lane dominates. Splitting MONEY further is possible but not
advisable: it is one transactional change to live payroll and cutting it in half doubles the
chance of shipping half of it.

---

## Lane assignments

Each lane runs in its own git worktree on branch `fleet/<lane>`, all branched from the Phase 0
commit. Lanes are grouped by **overlapping file set**, not by topic — that is what keeps the
merges cheap.

### Lane MONEY — `fleet/money` — task-55 — critical path
Implements decision-30: `worker_rates` history, `shift_edits`, `worker_rate_changes`, the
`withTransaction` helper, and one shared rate resolver.
**Owns:** migration `006`, `server/lib/db.js`, `server/lib/reporting.js`, `web/lib/payroll.ts`,
the worker sections of `server/routes/admin.js`.
**The trap:** the backfill must make the deploy arithmetically a no-op. Prove it with a
before/after diff over every existing period, do not assume it.
**Demo:** record a raise, then show a payroll report for a *prior* period still printing the
original figure.

### Lane SEC — `fleet/sec` — task-54
`APP_KEY` becomes a comma-separated set; repo goes private; per-IP rate limiting on
`/auth/code`; `ops/REBRAND.md:152` corrected.
**Owns:** `server/lib/auth.js`, `ops/REBRAND.md`.
**Blocks:** Phase 3 — both mobile builds carry the new key.
**Demo:** two curls with old and new key both 200; a junk key 401.

### Lane OPS — `fleet/ops` — task-57, task-62
Offsite restic backup, the `EnvironmentFile` fix that currently makes the offsite path abort on
first run, an actually-executed restore, a production restore runbook, `OnFailure=` alerting,
uptime polling, journald retention, resource limits.
**Owns:** `ops/backup/`, `ops/systemd/`, `ops/README.md`. Touches no application code.
**Demo:** pull the offsite backup to a scratch DB, restore, `SELECT` real shift rows.

### Lane CI — `fleet/ci` — task-56, task-66
The GitHub Actions workflow (Phase 0 already did the skip-fix and the db-guard port), plus
`ops/check-decisions.mjs` so `AGENTS.md` can never go stale against `backlog/decisions/` again.
**Owns:** `.github/`, `ops/check-decisions.mjs`.
**Demo:** open a PR with a deliberately broken payroll assertion, show CI red, fix, show green.

### Lane METRICS — `fleet/metrics` — task-58
`daily_metrics` rollup, failed-tap counter, `last_autoclose_run` on `/health`, a dashboard tile.
**Owns:** migration `007`, the rollup job, one web dashboard component.
**Why it matters:** the m-5 criterion *"10 consecutive working days with no lost shift"* is not
checkable without this. It is infrastructure for the milestone, not a feature.
**Demo:** answer the 10-day criterion from the dashboard rather than a manual query.

### Lane VOICE — `fleet/voice` — task-47
In-app feedback screen: server route, iOS, Android, admin queue.
**Owns:** a new server route, `NFCTimeSheets/`, `android/`, one web screen.
**Hard constraint from the task itself:** must not block or complicate clocking in. The tap path
is the product; do not put anything in front of it.
**Demo:** a worker sends a report from the app; it appears in the admin queue with app version,
platform and OS attached.

### Lane PM — `fleet/pm` — task-63, task-64, task-65
Definition of Done, AC backfill onto the 11 tasks with none, incident process, `INC-001`
retro-filed, field log, German worker card and director guide, `backlog/docs/` split by lifetime.
**Owns:** documentation only. **Zero code collision** — merges first, always.
**Demo:** not required (`demo.required: false`) — ships no user-visible behaviour.

### Lane FIELD — `fleet/field` — task-49
Analyse Balint's screen recording from the first Android field test. Read-only; produces
findings that become tasks.
**Demo:** not required.

---

## Merge order, and why it is this order

Phase 2 merges in **ascending order of collision surface**, so every conflict is resolved
against the smallest possible amount of already-merged change:

```
PM (docs, 0 collisions)
  → FIELD (0)
    → OPS (ops/ only, 0 with application code)
      → CI (.github/, 0)
        → SEC (server/lib/auth.js — 1 file, isolated)
          → METRICS (migration 007, admin.js read paths)
            → VOICE (new route + clients, light admin.js touch)
              → MONEY (migration 006, admin.js write paths, reporting, payroll)
```

MONEY merges **last** despite finishing last anyway, because it has the widest blast radius in
`server/routes/admin.js` and `server/lib/reporting.js`. Everything else is already settled when
it lands, so its conflicts are one-sided.

`task-59` (transactions on contract mutations, security headers, scrypt cost, `email_verified`
guard, payroll CSV truncation, `check-close-flag` rewrite) runs **after** the MONEY merge in
the main worktree, because it consumes the `withTransaction` helper MONEY introduces. Running
it in parallel would mean two lanes independently inventing the same helper.

---

## What the fleet cannot do

State these plainly rather than letting them surface as silent failures:

1. **Physical hardware.** Two m-5 exit criteria require a human tapping a real phone against a
   real tag on a real wall. `uses-feature nfc required="true"` is a Play *store filter only*, so
   `adb install` bypasses it and an NFC-less emulator runs green — which is exactly why the
   Android app has never once been proven. Agents must report `NEEDS_HUMAN`, never simulate it.
2. **Store review.** TestFlight and Play review are days of calendar time owned by Apple and
   Google.
3. **Ten calendar days.** The "10 consecutive working days" criterion is elapsed time. The fleet
   can only make it *measurable* (Lane METRICS), not make it *true*.
4. **The Google Maps key.** `ops/deploy.sh:44` passes only `NEXT_PUBLIC_DEFAULT_LOCALE`, so the
   Maps key is never inlined. Fixing that line is one thing; obtaining and installing the key,
   and enabling the Street View Static API on the Google project, is an owner console action.
5. **Signing the DPA** with the VM host, and with Sentry before a DSN is set.

---

## Rules every lane agent follows

1. **Read all 30 records in `backlog/decisions/` before writing code.** Not the summary in
   `AGENTS.md` — the records. The summary was eight days stale once and will be again.
2. **A decision is binding and changes only by supersession.** If your task appears to require
   contradicting one, STOP and report `newDecisionNeeded`. Do not proceed and explain later.
3. **Never append to `server/check-api.js`.** New assertions go in `server/checks/<feature>.check.js`
   and get one line in `ops/check-all.sh`.
4. **Never choose your own migration number.** Use the one reserved for you in Phase 0.
5. **Run checks with `REQUIRE_DB=1`.** A SKIP is a failure.
6. **Ship a demo, and do not certify your own.** `demo/<feature>.demo.sh`, non-interactive,
   guarded by `demo/db-guard.mjs`, exits non-zero when the thing is broken.
7. **Use the `backlog` CLI, not direct file edits,** for tasks, drafts and milestones
   (`AGENTS.md`). Decision *records* are the exception — the CLI only supports `decision create`,
   so status changes and supersession are hand edits.
8. **Never leave the worktree unrunnable.** If you pause, pause at a state where
   `ops/check-all.sh` passes.
9. **German and English stay at key parity.** `web/scripts/check.mjs` rule 2 enforces it.
10. **Do not write a live secret into any tracked file.** `.gitleaks.toml` allowlists `tsk_*` by
    design, so it will not catch you.

---

## Resumability

Every phase boundary is a resume point. The schemas in `docs/fleet-schemas/` are what make that
work: a later session reads `foundation.contract.json` and each `lane-result.json` and knows
exactly what is done, what is merged and what is outstanding — without re-reading the diff.

`fleet/<lane>` branches are not deleted on merge. A lane can be re-entered, re-run or reverted
independently.
