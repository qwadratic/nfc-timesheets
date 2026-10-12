# Independent shift evidence review gate

Reviewed 2026-10-10 in `codex/shift-evidence`, against base `41925c9`.
The code-review-and-quality skill was applied. All files in `backlog/decisions/`
were enumerated and read, including later amendments and superseding records.
Review covered tracked diffs and untracked implementation files for API/storage,
Android, iOS and web; generated logs and temporary build/fixture files were excluded.

## Verdict

No outstanding actionable implementation defect was identified after the corrections
below. This is a static review result, **not release approval**. The mandatory native
iOS compile/check and real feature verification remain incomplete; full completion
must not be claimed until those gates are satisfied. Dedicated feature reports own
their actual UI/device results and must be consulted separately.

## Findings corrected during review

1. **P1 — Android lost close response could strand an open local shift.**
   `TimeSheetViewModel.kt` previously always requested a new camera challenge before
   retrying a close. If the first close committed but its response was lost, the
   server rejected that challenge as `shift_not_active`; refresh ignored a null
   server-open row, leaving no recovery. This contradicted server authority and
   pending-work preservation (decisions 19 and 62). The new `closeWithEvidence`
   helper at lines 214–227 first retries the stored proof ID through idempotent close;
   only a missing/expired proof causes recapture. Both NFC/switch and manual close
   call it. Re-reviewed statically; response-loss device execution is still required.
2. **P2 — concurrent NFC events could overwrite the pending camera result.**
   `TimeSheetViewModel.kt:790` previously checked the busy flag, suspended while
   reading the open shift, then set the flag. Two arrivals could each create a
   challenge and overwrite `photoResult`, leaving one coroutine waiting forever.
   The gate now acquires the flag before launching/suspending and releases it in a
   whole-operation `finally`. This protects the requested completion flow and its
   decision-19 authoritative close. Re-reviewed the final guard placement.
3. **Required gate — branding initially failed after generalizing the debug port.**
   `ops/check-branding.mjs:235` expected the previous single fixture port. The gate
   now asserts all loopback URI restrictions: HTTP, literal 127.0.0.1, valid explicit
   port, no userinfo/query/fragment/path. Release resolver remains separately pinned
   to the configured API host. This preserves decisions 24/40/53, rather than removing
   the branding check.

## Decision and implementation checks

- No Docker/framework/router/ORM/new server package; PostgreSQL persists evidence
  (decisions 1/2/16/23). Migration is additive with disabled defaults and no invented
  historical evidence.
- Session-derived worker ownership, company RLS plus composite tenant foreign keys,
  and admin-only evidence/photo reads preserve decisions 22/50/66/72. Operator
  credentials never acquire a shift route (decisions 45/49).
- Server row locks serialize proof/close; every worker close and timeout-resolution
  path enforces proof. Automatic timeout itself remains independent (decision 10).
- Proof is camera-only in supported native UI; challenge precedes capture; bounded
  JPEG upload and expiry checks exist. A custom API client is not camera-attested,
  which is accurately documented rather than claimed.
- Android visible location service is limited to active shifts/session and a location
  foreground-service type. No boot tracking or reminder special-use service is added.
  iOS Core Location is shift-scoped with a visible indicator and expiry stop. OS
  delivery cadence is explicitly best-effort, not a promised exact background timer.
- Pending shift stores are migrated without wiping queues (decision 62). New iOS
  files use the existing synchronized group; entitlement/project.pbxproj unchanged
  (decisions 24/49).
- New user-facing keys have German and English entries on all platforms (decision 8),
  including iOS permission descriptions. Web components use `useTranslations`.
- Sensitive coordinate/photo fields were added to all four telemetry scrubbers
  (decisions 23/70). Private JPEG responses use `no-store` and `nosniff`.
- Policy is snapshotted per new shift and the admin wording states that limitation.
  Photos/locations do not enter payroll formulas, portal payloads or zone resolution.

## Verification evidence and limits

- Independently ran `node ops/check-branding.mjs` after the correction: **OK**, all
  checks passed, **no TODO lines**. The complete non-ok output is therefore empty.
- Independently ran `git diff --check`: passed.
- Reviewer attempt to run `NFCTimeSheets/checks/run.sh` via Git Bash failed before
  execution with sandbox MSYS `NtCreateDirectoryObject ... 0xC0000022`. The parent
  separately ran that gate elevated and reported its actual result:
  `checks: swift not found. Install Xcode or the Command Line Tools.` No Swift
  compilation, simulator run or iPhone background/camera test is represented here.
- Parent reports successful web `pnpm verify`, Android core checks/debug build, and
  authenticated API/evidence checks against real isolated PostgreSQL. These are
  attributed results, not independent reruns by this reviewer. The parent also reports
  a full legacy API-suite uniqueness failure; it is not counted as a pass here.
- Native real-action matrices belong to `docs/shift-location-verification.md`,
  `docs/shift-proof-verification.md`, and
  `NFCTimeSheets/checks/shift-evidence-verification.md`. Pending matrix rows remain
  pending regardless of this static review verdict.

No production change, migration, signing, push or deployment was performed by this review.

## Combined PR integration re-review

Reviewed the integration of PR 16 (`cec1092`) on 2026-10-10. Decisions 75, 77, 78
and 79 were read in addition to the original decision review; decision 79's referenced
`docs/AGENT-INTEGRATION.md` was inspected. The review was confined to the integration
delta rather than repeating the original independent reviews.

**Draft publication verdict: clear.** No integration code blocker found. Agent routes
remain under `/agent/` with an explicit allowlist; evidence worker/admin routes preserve
their authentication and tenant scope. Evidence settings remain mounted in the merged
setup page. New shared database savepoint support does not replace the evidence row-lock
transactions. The migration sequence is now 026 agent tokens, 027 tool calls, 028 shift
evidence; the resolved workspace-test helper applies all three in order. The original
026 evidence migration was renamed before deployment, not duplicated.

Independently repeated branding: **OK, no TODOs**. Independently ran agent catalog tests:
**4/4 passed**. The parent reports combined workspace/evidence, 53 agent tools, MCP bridge
and full web verification passing. Evidence endpoints are intentionally not exposed by
the 53-tool catalog, and the combined feature documentation states this.

**Release documentation blocker:** incoming `docs/play-publication/` drafts describe
the old 0.5.10 app and explicitly deny location/photos (store-listing, privacy-policy,
data-safety) and a foreground service (declarations). Those statements are false for
this combined feature build. They must be revised or clearly marked historical and
not publishable for this build. This does not prevent a draft PR but prevents using
those texts as the release's disclosure. Earlier native verification limits remain.
