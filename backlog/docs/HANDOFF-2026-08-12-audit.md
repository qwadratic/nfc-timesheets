# Handoff — 2026-08-12 backlog audit and fleet plan

**For:** the next agent system, or the next human
**Branch:** `plan/agent-fleet-2026-08-12` · **HEAD:** `dfc7426` · **Tree:** clean except one
untracked directory, deliberately (see §5)
**Previous state:** `75834a2` on `main`

---

## 1. What this session did

Audited the backlog for contradictions against accepted decisions, fixed everything mechanical,
and produced a build plan. **No application code was touched.** The system runs exactly as it
did before — every change is documentation, decision records, or backlog metadata.

Four parallel auditors ran. Two died mid-run on API connection errors and were re-run with
tighter scope; their replacements completed. Findings below are from the completed runs.

## 2. Decisions you must not re-litigate

Three were taken with the human in this session. They are settled.

| | Decision | Why |
|---|---|---|
| **D1** | Repo goes **private**; `APP_KEY` becomes a comma-separated **set**; rotate at the next store release | The live key is readable in a public repo, and `server/lib/auth.js:37` accepts exactly one value, so rotating today bricks clock-in for every worker until Apple *and* Play finish review. The key-set change turns every future rotation into a rolling migration. → **task-54** |
| **D2** | **Full** `worker_rates` history, not the cheap append-only log | Asked for "the full good quality solution". Its only real risk — historical reports changing value on deploy — is removed by seeding each worker's current rate at their earliest shift date, which makes the migration arithmetically a no-op. → **decision-30**, **task-55** |
| **D3** | Finish line is **m-5 Vienna Pilot** — make the one existing customer reliable | Field evidence: a worker could not clock out on 2026-08-11, and the Android app has never once run on physical hardware. Play listing, white-label, CI-as-product and staging deferred to **m-6**. |

`decision-30` supersedes `decision-28` and answers all four gate questions that record set as a
precondition. Read it before touching payroll.

## 3. What changed on the board

- **Decision ledger repaired.** Was: two files both claiming `decision-28`, a missing
  `decision-25` cited by `decision-27`, and `decision-7` still `accepted` eight days after being
  superseded. Now: 30 sequential ids, no collisions, no gaps, every status truthful, tombstone
  at 25.
- **Stale docs corrected.** `state.md` reduced to a pointer (it claimed "Not deployed", "PM2",
  "Android: research only" — all false for ~2 weeks). `AGENTS.md` checklist brought current
  through decision-30. `Backlog.md` frozen with a danger banner listing its 14 contradictions.
  Two false claims removed from `README.md`.
- **Task statuses corrected.** task-50 was shipped but marked To Do. task-23, task-24 marked
  obsolete (they describe reverted behaviour). task-48 closed as a duplicate of task-16.
  task-38 merged into task-57. ACs that could never pass (task-15's "Login page accepts PIN")
  rewritten.
- **Priority re-triaged.** Was 41 of 53 at `high` — a field carrying no information, while the
  offsite-backup and blind-Sentry tasks sat at `medium`. Now: `high` means it blocks an m-5 exit
  criterion. Exactly ten do.
- **15 new tasks** (54–68) from the audit.

## 4. Where to start

**Read first:** `docs/AGENT-FLEET-PLAN.md`. It has the graph, the lane assignments, and the
collision analysis that justifies them.

**Then run Phase 0 and stop.** It is serial, blocking, ~1h, and it is the whole reason eight
lanes can run at once:

```
ops/fleet/m5-pilot.workflow.js     # written, parses, NEVER RUN
docs/fleet-schemas/*.json          # the contracts between phases
```

Phase 0 does four things: splits `server/check-api.js` (3375 lines that every lane wants to
append to) into `server/checks/<feature>.check.js` + an append-only `ops/check-all.sh` manifest;
makes a SKIP a failure under CI; ports `demo/db-guard.mjs`'s protections into `check-api.js`;
and reserves migration numbers (006 → MONEY, 007 → METRICS) so no lane picks its own.

**Do not fan out before Phase 0 lands.** Eight lanes on an unsplit check harness produce eight
conflicting edits to one file, and the merge costs more than the work did.

**Critical path** is Phase 0 → lane MONEY (~10 agent hours) → task-59 → gate. The other seven
lanes finish inside MONEY's shadow. Do not split MONEY: it is one transactional change to live
payroll, and halving it doubles the chance of shipping half of it.

## 5. Things that will bite you

**A second writer was active in this working tree during this session.** Commit `e0281d5`
(`ops/sync-secrets.sh`, author `qwadratic`, 06:44) appeared on this branch after it was created,
and 52 screenshots appeared in `docs/media/states/` between 06:52 and 07:08. Neither was made by
the audit session. `docs/media/states/` is **left untracked on purpose** — the files are named
`*-populated-*.png` and task-37 exists because an unredacted client-name screenshot once leaked
into public git history. Someone who knows what they are should look before committing or
deleting them. → **task-68**, which also notes the fleet plan assumes a single writer and needs
a concurrency rule.

**The pre-commit hook's bypass is mis-scoped.** `PSST_SKIP_SCAN=1` hits `exit 0` on line 6 of
`.githooks/pre-commit` and skips **gitleaks too**, despite its name. This commit needed the
bypass because psst flags `ordinal: 18000/38000/48000/58000` as containing the vault value of
`PORT` (`8000`) — a substring false positive on a backlog-CLI-generated field that will recur
on roughly one task in ten. gitleaks was run separately and explicitly (0 leaks) to preserve the
coverage the flag silently drops. → **task-67**

**Five things the fleet structurally cannot do**, and must report as `NEEDS_HUMAN` rather than
simulate: physical hardware proof (`uses-feature nfc` is a Play store *filter only*, so an
NFC-less emulator runs green — which is exactly why Android has never been proven), store review,
ten elapsed calendar days, the Google Maps key (`ops/deploy.sh:44` passes only
`NEXT_PUBLIC_DEFAULT_LOCALE`, so the key is never inlined), and signing the DPAs.

**One line unblocks three tasks.** Fixing `ops/deploy.sh:44` plus installing
`GOOGLE_GEOCODING_KEY` on the server unblocks task-16 AC1–3 and task-17 AC1 simultaneously.
Highest ratio of unblock to effort on the board.

## 6. What was NOT done

- No application code written. No migration created. Nothing deployed.
- The fleet has not run. `ops/fleet/m5-pilot.workflow.js` parses and is reviewed, but Phase 0
  has never executed.
- `backlog/docs/` still holds 15 expired session reports mixed with 3 load-bearing documents
  that `README.md` links to. Filed as task-65, not done — it is a file move that would have
  collided with everything else in this commit.
- The 11 tasks with zero acceptance criteria still have none. Filed as task-63.

## 7. Resume in one line

```
git checkout plan/agent-fleet-2026-08-12 && backlog task 54 --plain   # or read docs/AGENT-FLEET-PLAN.md
```

The tree is runnable. Nothing is half-applied. Every phase boundary in the plan is a resume
point, and the schemas in `docs/fleet-schemas/` are what let a later session know what is done
without re-reading the diff.
