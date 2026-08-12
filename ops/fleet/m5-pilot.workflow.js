export const meta = {
  name: 'm5-vienna-pilot',
  description: 'Build the m-5 Vienna Pilot backlog: 8 parallel worktree lanes, schema-gated phases, demo per feature',
  whenToUse: 'After docs/AGENT-FLEET-PLAN.md has been reviewed and Phase 0 is authorised to run.',
  phases: [
    { title: 'Foundation', detail: 'serial, blocking: check-harness split, skip-fails-under-CI, db-guard, migration numbers' },
    { title: 'Lanes', detail: '8 parallel worktrees: PM FIELD OPS CI SEC METRICS VOICE MONEY' },
    { title: 'Verify', detail: 'each lane demo verified by a DIFFERENT agent than built it' },
    { title: 'Integrate', detail: 'merge in ascending collision order, then task-59' },
    { title: 'Gate', detail: 'decision compliance + pilot exit criteria + handoff memo' },
  ],
}

// ---------------------------------------------------------------------------
// Read before editing: docs/AGENT-FLEET-PLAN.md explains WHY the lanes are
// grouped this way. The grouping is by overlapping file set, not by topic.
// ---------------------------------------------------------------------------

const REPO = '/Users/gerhardgustav/Desktop/ai-automations/hoiv/cleaning-timesheets'

const RULES = `
NON-NEGOTIABLE RULES (docs/AGENT-FLEET-PLAN.md "Rules every lane agent follows"):
1. Read ALL 30 records in backlog/decisions/ before writing code. Not the AGENTS.md summary --
   the records. That summary was eight days stale once already.
2. A decision is binding and changes ONLY by supersession. If your task seems to require
   contradicting one, STOP and report newDecisionNeeded. Do not proceed and explain later.
3. NEVER append to server/check-api.js (3375 lines, every lane wants it -- that is the worst
   merge conflict in this plan). New assertions go in server/checks/<feature>.check.js and get
   ONE line in ops/check-all.sh.
4. NEVER choose your own migration number. Use the one reserved for you in Phase 0.
5. Run checks with REQUIRE_DB=1. A SKIP is a FAILURE -- "passed" and "never ran" must not be
   indistinguishable.
6. Ship a demo: demo/<feature>.demo.sh, non-interactive, guarded by demo/db-guard.mjs, exits
   non-zero when the thing it demonstrates is broken. You may NOT certify your own demo.
7. Use the backlog CLI for tasks/milestones, not direct file edits (AGENTS.md). Decision RECORDS
   are the exception: the CLI only supports 'decision create'.
8. Never leave the worktree unrunnable. If you pause, pause where ops/check-all.sh passes.
9. German and English stay at key parity (web/scripts/check.mjs rule 2).
10. Never write a live secret into a tracked file. .gitleaks.toml allowlists tsk_* by design,
    so it will NOT catch you.
11. Physical hardware and store review CANNOT be done by an agent. Report NEEDS_HUMAN. Never
    simulate, never silently skip.
`

const LANE_RESULT_SCHEMA = {
  type: 'object',
  required: ['lane', 'tasks', 'filesTouched', 'checks', 'demo', 'decisionCompliance', 'status', 'handoff'],
  properties: {
    lane: { type: 'string' },
    tasks: { type: 'array', items: { type: 'string' } },
    filesTouched: { type: 'array', items: { type: 'string' } },
    migrations: { type: 'array', items: { type: 'object' } },
    checks: {
      type: 'object',
      required: ['suiteAdded', 'registeredInManifest', 'assertionsAdded', 'allSuitesPass'],
      properties: {
        suiteAdded: { type: 'string' },
        registeredInManifest: { type: 'boolean' },
        assertionsAdded: { type: 'integer' },
        allSuitesPass: { type: 'boolean' },
      },
    },
    demo: {
      type: 'object',
      required: ['required', 'scripts'],
      properties: {
        required: { type: 'boolean' },
        scripts: { type: 'array', items: { type: 'object' } },
      },
    },
    decisionCompliance: {
      type: 'object',
      required: ['decisionsRead', 'violations', 'newDecisionNeeded'],
      properties: {
        decisionsRead: { type: 'integer' },
        violations: { type: 'array', items: { type: 'object' } },
        newDecisionNeeded: { type: ['string', 'null'] },
      },
    },
    status: { type: 'string', enum: ['DONE', 'DONE_WITH_CONCERNS', 'BLOCKED', 'NEEDS_HUMAN'] },
    concerns: { type: 'array', items: { type: 'string' } },
    handoff: { type: 'string' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['result', 'observedOutput', 'reasoning'],
  properties: {
    result: { type: 'string', enum: ['PASS', 'FAIL'] },
    observedOutput: { type: 'string' },
    reasoning: { type: 'string' },
  },
}

// ---------------------------------------------------------------------------
// PHASE 0 -- FOUNDATION. Serial and blocking. Without this, eight lanes produce
// eight conflicting edits to server/check-api.js and the merge costs more than
// the work did.
// ---------------------------------------------------------------------------
phase('Foundation')
log('Phase 0: making the repo safe for eight concurrent lanes')

const foundation = await agent(
  `${RULES}

You are the FOUNDATION agent for ${REPO}. You run ALONE, on the main worktree, before any
other agent starts. Four jobs, in this order:

F1. SPLIT THE CHECK HARNESS. server/check-api.js is 3375 lines and every downstream lane wants
    to append assertions to it. Create the convention server/checks/<feature>.check.js and an
    append-only manifest ops/check-all.sh that runs every suite. Register ALL 15 existing
    harnesses in it: server/check-api.js, server/db/check-migrate.js, server/routes/wellknown.test.js,
    server/check-telemetry-wire.mjs, server/check-close-flag.mjs, web/scripts/check.mjs,
    ops/check-branding.mjs, ops/check-autoclose.sh, demo/check-guards.sh,
    NFCTimeSheets/checks/run.sh, android/checks/run.sh, and any others you find. 13 of 15 are
    currently unreachable from any package manager.

F2. MAKE A SKIP A FAILURE UNDER CI. server/check-api.js:211-214 and server/db/check-migrate.js:24-25
    print SKIP and exit 0 when no database is reachable. Correct on a laptop, dangerous in CI.
    Under CI=1 or REQUIRE_DB=1 they must exit 1 with the same message. PROVE it by running with
    the var set and no database, and observing a non-zero exit.

F3. PORT THE DB GUARD. server/check-api.js:45 defaults DATABASE_URL with no loopback check, no
    host= query-param check, no PGHOST check and no DB-name check -- point it at production and
    it CREATE SCHEMAs on the live payroll database. demo/db-guard.mjs already defeats all four
    and proves it in demo/check-guards.sh (16 cases). Port assertDemoDatabase into check-api.js.
    PROVE it by pointing DATABASE_URL at a non-loopback host and observing a refusal.

F4. RESERVE MIGRATION NUMBERS. Two lanes both writing 006_*.sql collide unrecoverably. Reserve:
      006 -> lane MONEY   -> 006_worker_rates_and_audit.sql   -> kind: expand
      007 -> lane METRICS -> 007_daily_metrics.sql            -> kind: expand
    Write these into the contract you return. No lane may choose its own number.

Commit your work. Return a foundation contract matching the schema. Every 'verified' field must
be true and must reflect something you actually ran, not something you believe.`,
  {
    label: 'foundation',
    phase: 'Foundation',
    schema: {
      type: 'object',
      required: ['baselineCommit', 'checkHarnessSplit', 'skipFailsUnderCI', 'dbGuardPorted', 'migrationNumbersReserved'],
      properties: {
        baselineCommit: { type: 'string' },
        checkHarnessSplit: { type: 'object' },
        skipFailsUnderCI: { type: 'object' },
        dbGuardPorted: { type: 'object' },
        migrationNumbersReserved: { type: 'array', items: { type: 'object' } },
        notes: { type: 'string' },
      },
    },
  },
)

if (!foundation) {
  log('FOUNDATION FAILED — refusing to fan out. Eight lanes on an unsplit check harness is worse than serial.')
  return { status: 'BLOCKED', reason: 'Phase 0 did not complete', foundation: null }
}
log(`Foundation done at ${foundation.baselineCommit}. Migration numbers reserved. Fanning out.`)

// ---------------------------------------------------------------------------
// PHASE 1+2 -- LANES, each pipelined straight into its own demo verification.
// pipeline() not parallel(): a lane that finishes early gets verified while the
// slow lanes are still building. MONEY dominates at ~10h; the others finish in
// its shadow and there is no reason to make them wait at a barrier.
// ---------------------------------------------------------------------------
const LANES = [
  {
    key: 'PM', branch: 'fleet/pm', tasks: ['task-63', 'task-64', 'task-65'], demoRequired: false,
    brief: `Documentation and process only. ZERO code. You merge first because you collide with nothing.
      task-63: write backlog/docs/DEFINITION-OF-DONE.md specific to THIS stack, and backfill acceptance
        criteria onto the 11 tasks that have none (task-30,31,45,46,47,48,49,50,51,52,53). Add an effort
        field (S<2h / M half-day / L multi-day-split-it) sized in AGENT hours.
      task-64: backlog/docs/INCIDENTS.md with three severities in this product's terms (S1 a worker
        cannot clock in/out or hours are lost; S2 the director cannot run payroll; S3 cosmetic).
        Retro-file the 2026-08-11 adopted-tag incident as INC-001 -- it is fresh and makes the template
        concrete. Add backlog/docs/FIELD-LOG.md with a fixed template. Write a one-page GERMAN worker
        card and a GERMAN director guide -- extract from android/README.md:582 and
        backlog/docs/ADMIN-WALKTHROUGH.md, which already hold the content. Every doc in this repo is
        currently developer-facing and English, for a German-speaking customer.
      task-65: split backlog/docs by LIFETIME. Move runbook-vm-provisioning.md, DEMO.md and
        V2-FEATURES.md to docs/ (README links to all three) and the other 15 session reports to
        backlog/archive/docs/. Add the rule to AGENTS.md.`,
  },
  {
    key: 'FIELD', branch: 'fleet/field', tasks: ['task-49'], demoRequired: false,
    brief: `Read-only research. Analyse Balint's screen recording from the first Android field test
      (2026-08-11). Findings become backlog tasks via the CLI. Do not change application code.
      This is the only direct evidence of the product failing in a real stairwell -- treat it as
      the highest-signal artifact in the repo.`,
  },
  {
    key: 'OPS', branch: 'fleet/ops', tasks: ['task-57', 'task-62'], demoRequired: true,
    brief: `ops/ only -- no application code, so you collide with nobody.
      FIX THE UNIT FIRST: ops/systemd/nfc-backup.service has NO EnvironmentFile, but
      ops/backup/pg-backup.sh:69-76 tells the operator to put offsite credentials in /etc/nfc/env and
      dereferences $RESTIC_REPO under set -u. The offsite work as documented ABORTS on first run.
      ProtectSystem=strict plus a single ReadWritePaths=/var/backups/nfc will also block restic cache
      paths. Then: restic offsite target (encrypted -- dumps contain RAW sessions.token, so a stolen
      dump yields working admin sessions for 7 days), credential in psst never in git, EXECUTE the
      restore and record the date at ops/backup/restore-test.sh:11 and ops/README.md:108, write a
      PRODUCTION restore runbook with a stated RTO (restore-test.sh only touches a scratch DB, so
      none exists), OnFailure= alert units, external /health polling, journald SystemMaxUse=,
      MemoryMax and StartLimitBurst on nfc-api.service.
      DEMO: pull the offsite backup to a scratch DB, restore it, SELECT real shift rows.`,
  },
  {
    key: 'CI', branch: 'fleet/ci', tasks: ['task-56', 'task-66'], demoRequired: true,
    brief: `Phase 0 already did the skip-fix and the db-guard port -- do NOT redo them.
      task-56: .github/workflows/ci.yml with a postgres:16 service container, running ops/check-all.sh.
        Include the ops job that asserts generated well-known files match branding.json:
        node ops/gen-wellknown.mjs && git diff --exit-code server/wellknown/.
        Delete the three empty XCTest template files -- they build green, assert nothing, and their
        presence implies tests that do not exist.
      task-66: ops/check-decisions.mjs asserting every file in backlog/decisions/ appears in the
        AGENTS.md checklist, nothing superseded is listed as binding, and decision IDs are unique and
        contiguous. The 2026-08-12 audit found TWO files claiming decision-28 and a missing
        decision-25; the checklist was 8 days stale. Wire into CI and the pre-commit hook.
      DEMO: PR with a deliberately broken payroll assertion -> CI red -> fix -> green.`,
  },
  {
    key: 'SEC', branch: 'fleet/sec', tasks: ['task-54'], demoRequired: true,
    brief: `server/lib/auth.js and ops/REBRAND.md. Isolated, one file of application code.
      APP_KEY becomes a comma-separated SET; auth.js accepts any member via safeEqual, still
      constant-time per candidate; empty set refuses to BOOT. Flip the repo private
      (gh repo edit proximata/nfc-timesheets --visibility private). Add per-IP rate limiting on
      POST /auth/code -- server/lib/auth.js:297-314 is currently a process-GLOBAL 30/min ceiling, so
      any anonymous caller can hold it at zero and permanently deny enrolment to real workers.
      Correct ops/REBRAND.md:152: it says edit Branding.swift, but the literal is at API.swift:52, so
      following the runbook rotates server and Android but NOT iOS.
      DO NOT flip the server key. Generate the new one and ADD it to the set; it ships in Phase 3.
      DEMO: old key 200, new key 200, junk key 401.`,
  },
  {
    key: 'METRICS', branch: 'fleet/metrics', tasks: ['task-58'], demoRequired: true,
    brief: `Migration 007 (RESERVED -- do not choose another number). daily_metrics rollup following the
      existing ops/systemd/nfc-autoclose.timer pattern. No vendor: decision-16 and decision-23 set a
      dependency budget and a nightly SQL rollup over data already in Postgres gets you activation,
      shifts/day, auto-close rate and correction rate. Add a failed-tap counter posted with the next
      successful sync -- the tap that fell back to Safari is currently only a Sentry warn at
      server/routes/wellknown.js:80 that goes NOWHERE. Report last_autoclose_run from /health so a
      stalled timer is visible from outside the box (a non-firing 8h timer means every open shift runs
      all weekend and the director finds out from a wrong payroll number).
      This is what makes the m-5 criterion "10 consecutive working days with no lost shift" checkable
      at all. It is milestone infrastructure, not a feature.
      DEMO: answer the 10-day criterion from the dashboard, not a manual query.`,
  },
  {
    key: 'VOICE', branch: 'fleet/voice', tasks: ['task-47'], demoRequired: true,
    brief: `Cross-platform: new server route + iOS + Android + one admin screen.
      HARD CONSTRAINT from the task itself: MUST NOT block or complicate clocking in. The tap path is
      the product. Nothing goes in front of it.
      Today the system is silent in one direction -- a worker who cannot clock out, finds a dead tag or
      sees a wrong shift has no way to say so from inside the app. The only channel is phoning the
      director, so the director learns about it from a payroll number that looks wrong weeks later.
      Auto-attach app version, platform and OS; that is what makes a report actionable.
      DEMO: worker sends a report from the app, it appears in the admin queue with the metadata.`,
  },
  {
    key: 'MONEY', branch: 'fleet/money', tasks: ['task-55'], demoRequired: true,
    brief: `CRITICAL PATH, ~10 agent hours, widest blast radius. Implements decision-30 -- read that
      record in full before touching anything; it answers four gate questions and you must not
      re-litigate them.
      Migration 006 (RESERVED). worker_rates, shift_edits, worker_rate_changes. withTransaction helper
      in server/lib/db.js -- server/ currently has NO transactions at all (pool.connect/BEGIN appear
      nowhere). ONE shared rate resolver used by GET /admin/data hours, server/lib/reporting.js AND
      web/lib/payroll.ts: if payroll and the P&L disagree, nothing on screen says which is lying.
      THE TRAP: the backfill seeds each worker's CURRENT rate at valid_from = earliest of (their
      earliest shift date, worker created_date). That makes the deploy arithmetically a NO-OP. PROVE
      it with a before/after diff of GET /admin/data and GET /admin/pl over every existing period
      showing ZERO changed values. Do not assume it.
      Keep workers.hourly_rate_cents as a MIRROR of the current row (the locations.monthly_contract_cents
      precedent) -- dropping it breaks the shipped iOS response shape.
      Close audit P14 while you are here: reporting.js:124 rounds per (worker,location) while
      admin.js:228 rounds per worker, diverging up to 0.5c x (N-1) for a worker at N buildings.
      Two admin actions, not one: "Record a raise" (forward-dated, default) and "Correct a mistake"
      (retroactive, reason REQUIRED).
      Remove GET /admin/pl's labour.rate_basis "current" marker and its German note -- the limitation
      no longer exists and leaving them would be a new lie.
      DEMO: record a raise, then show a payroll report for a PRIOR period still printing the original
      figure; then edit a shift and show the shift_edits row naming who, when, old value and why.`,
  },
]

phase('Lanes')
log(`Fanning out ${LANES.length} lanes. MONEY is the long pole (~10h); the rest finish in its shadow.`)

const laneResults = await pipeline(
  LANES,
  // Stage 1: build, in an isolated worktree
  (lane) =>
    agent(
      `${RULES}

You are lane ${lane.key}, working in ${REPO} on branch ${lane.branch}.

Foundation contract from Phase 0 (already landed — do NOT redo this work):
${JSON.stringify(foundation, null, 2)}

Backlog tasks assigned to you: ${lane.tasks.join(', ')}
Read each with: backlog task <id> --plain

YOUR BRIEF:
${lane.brief}

Demo required: ${lane.demoRequired ? 'YES — a feature without a runnable demo BLOCKS the gate' : 'NO — this lane ships no user-visible behaviour'}

When done: commit, mark your tasks Done via the backlog CLI with implementation notes, and return
a lane result. Set status NEEDS_HUMAN (not DONE) for anything requiring physical hardware, store
review or an owner console action. Be honest in 'concerns' — a lane that hides a concern makes the
gate useless.`,
      { label: `lane:${lane.key}`, phase: 'Lanes', schema: LANE_RESULT_SCHEMA, isolation: 'worktree' },
    ),
  // Stage 2: verify the demo — a DIFFERENT agent than the one that built it
  (result, lane) => {
    if (!result) return null
    if (!lane.demoRequired) return { ...result, demoVerdict: { result: 'PASS', reasoning: 'no demo required for this lane' } }
    return agent(
      `You are an INDEPENDENT verifier in ${REPO}. You did NOT build this and you are not here to
be agreeable. Lane ${lane.key} claims it finished ${lane.tasks.join(', ')} and shipped a demo.

Its self-report:
${JSON.stringify(result, null, 2)}

Do this:
1. Check out branch ${lane.branch}.
2. Actually RUN each demo script it claims. Paste what you observed — do not summarise it.
3. Verify the demo would FAIL if the feature were broken. A demo that always exits 0 proves
   nothing; try breaking the thing and confirm the demo notices.
4. Run ops/check-all.sh with REQUIRE_DB=1. Any SKIP is a FAIL.
5. Confirm it did NOT append to server/check-api.js and did NOT invent a migration number outside
   the Phase 0 reservation.
6. Spot-check its decisionCompliance claim against 2-3 of the 30 records in backlog/decisions/.

Return FAIL if the demo does not exist, does not run, cannot fail, or if any rule was broken.
Defaulting to PASS because it looks plausible is the failure mode this stage exists to prevent.`,
      { label: `verify:${lane.key}`, phase: 'Verify', schema: VERDICT_SCHEMA },
    ).then((v) => ({ ...result, demoVerdict: v }))
  },
)

const lanes = laneResults.filter(Boolean)
const failed = lanes.filter((l) => l.demoVerdict?.result === 'FAIL' || l.status === 'BLOCKED')
const needsHuman = lanes.filter((l) => l.status === 'NEEDS_HUMAN')
log(`${lanes.length}/${LANES.length} lanes returned. ${failed.length} failed verification. ${needsHuman.length} need a human.`)

// ---------------------------------------------------------------------------
// PHASE 3 -- INTEGRATION. Serial, main worktree, ascending collision order so
// every conflict resolves against the smallest already-merged surface.
// ---------------------------------------------------------------------------
phase('Integrate')
const MERGE_ORDER = ['PM', 'FIELD', 'OPS', 'CI', 'SEC', 'METRICS', 'VOICE', 'MONEY']
const mergeable = MERGE_ORDER.filter((k) => lanes.some((l) => l.lane === k && l.demoVerdict?.result !== 'FAIL' && l.status !== 'BLOCKED'))

const integration = await agent(
  `${RULES}

You are the INTEGRATION agent in ${REPO}, on the main worktree.

Merge these lane branches in EXACTLY this order — it is ascending collision surface, so every
conflict resolves against the smallest possible amount of already-merged change:
${mergeable.map((k) => `  fleet/${k.toLowerCase()}`).join('\n')}

MONEY merges LAST on purpose: it has the widest blast radius in server/routes/admin.js and
server/lib/reporting.js, so by the time it lands everything else is settled and its conflicts are
one-sided.

Lane results:
${JSON.stringify(lanes.map((l) => ({ lane: l.lane, tasks: l.tasks, files: l.filesTouched, status: l.status, concerns: l.concerns })), null, 2)}

${failed.length ? `DO NOT MERGE these — they failed verification: ${failed.map((f) => f.lane).join(', ')}` : 'All lanes passed verification.'}

After the merges, implement task-59 (transactions on contract mutations, security headers, scrypt
cost + rehash-on-login, the email_verified guard, payroll CSV truncation, check-close-flag rewrite).
It runs HERE and not as a lane because it consumes the withTransaction helper MONEY introduces —
running it in parallel would mean two lanes independently inventing the same helper.

After every merge step run ops/check-all.sh with REQUIRE_DB=1. Do not proceed past a red suite.
Leave the tree runnable at every commit.`,
  {
    label: 'integrate',
    phase: 'Integrate',
    schema: {
      type: 'object',
      required: ['merged', 'conflicts', 'checksPass', 'headCommit', 'status'],
      properties: {
        merged: { type: 'array', items: { type: 'string' } },
        skipped: { type: 'array', items: { type: 'string' } },
        conflicts: { type: 'array', items: { type: 'object' } },
        checksPass: { type: 'boolean' },
        headCommit: { type: 'string' },
        status: { type: 'string' },
        notes: { type: 'string' },
      },
    },
  },
)

// ---------------------------------------------------------------------------
// PHASE 4 -- GATE. Hostile by design: its job is to find reasons not to ship.
// ---------------------------------------------------------------------------
phase('Gate')
const gate = await agent(
  `You are the REVIEW GATE in ${REPO}. AGENTS.md defines this role: you run AFTER all
implementation, you read every decision record yourself, and you BLOCK completion if violations
exist. Your verdict overrides every lane's self-report.

Your job is to find reasons NOT to ship. "Everything passed" must be earned.

1. DECISION COMPLIANCE. Read all 30 files in backlog/decisions/ (ls, then read each). Verify no
   merged code contradicts any accepted decision. Verify the AGENTS.md checklist lists every
   record and marks nothing superseded as binding — it went 8 days stale once already.
2. DEMOS. Every feature must have one that RUNS and that CAN FAIL. A feature without a working
   demo is a BLOCK, not a concern.
3. CHECKS. ops/check-all.sh with REQUIRE_DB=1. skipsObserved MUST be 0.
4. PILOT EXIT CRITERIA. Score honestly against backlog/milestones/m-5 - vienna-pilot.md. Expect
   partials: two criteria need physical hardware and one needs ten elapsed calendar days. Mark
   those NEEDS_HUMAN / NEEDS_ELAPSED_TIME — never MET.
5. HANDOFF MEMO. Write backlog/docs/HANDOFF-<date>.md: what shipped, what is merged, what is
   outstanding, what needs a human, and the exact next action. Required regardless of verdict.

Integration result:
${JSON.stringify(integration, null, 2)}

Lanes needing a human: ${needsHuman.map((l) => `${l.lane} (${l.tasks.join(',')})`).join(', ') || 'none'}

BLOCK on: any decision violation, any missing or failing demo, any non-zero skip count, any lane
reporting BLOCKED.`,
  {
    label: 'gate',
    phase: 'Gate',
    effort: 'high',
    schema: {
      type: 'object',
      required: ['verdict', 'decisionViolations', 'demosVerified', 'skipsObserved', 'pilotExitCriteria', 'handoffMemoPath'],
      properties: {
        verdict: { type: 'string', enum: ['SHIP', 'SHIP_WITH_CONCERNS', 'BLOCK'] },
        decisionViolations: { type: 'array', items: { type: 'object' } },
        demosVerified: { type: 'integer' },
        skipsObserved: { type: 'integer' },
        pilotExitCriteria: { type: 'array', items: { type: 'object' } },
        concerns: { type: 'array', items: { type: 'string' } },
        handoffMemoPath: { type: 'string' },
      },
    },
  },
)

return {
  foundation,
  lanes: lanes.map((l) => ({ lane: l.lane, tasks: l.tasks, status: l.status, demo: l.demoVerdict?.result })),
  failedVerification: failed.map((f) => f.lane),
  needsHuman: needsHuman.map((l) => ({ lane: l.lane, tasks: l.tasks })),
  integration,
  gate,
}
