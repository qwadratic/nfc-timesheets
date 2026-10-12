# Shift location and camera proof (TASK-368)

Developed in `codex/shift-evidence`, based on `41925c9`, in a separate worktree.
No production deployment, migration, release signing, or change to another agent's checkout.

## Combined PR integration

PR #16 at `cec1092` is included in this branch. Its agent migrations retain numbers
026/027; shift evidence is now 028. The workspace test database applies all three in
that order. The combined branch passed workspace/evidence integration, the 53-tool
agent integration suite, four catalog tests, MCP bridge checks, branding and full web
verification. Native implementation is unchanged by this integration; the iOS and
physical-device verification limits below still apply. The 53-tool catalog does not
yet expose the new shift-evidence settings or private photo endpoints.

## Administrator workflow

Open company setup, select the company step, and use **Shift evidence / Schichtnachweise**.
Location capture can be disabled or set to an interval from 1 to 1,440 minutes (whole seconds).
Photo proof is a separate on/off setting. Both default to off. Save applies only to newly
opened server shifts; an already-open shift retains its policy snapshot.

In the shift correction drawer, expand **Photo and location evidence** to read recorded
positions and open the submitted photo. These reads require the same company's admin
session. This is observed device evidence, not independent proof of presence or image authenticity.

## Worker workflow

- Location permission is requested for an active shift with location enabled. Collection
  stops when the shift ends, the worker signs out, or the eight-hour limit is reached.
- Android uses a visible location foreground service. The existing shift reminder system
  remains independent. iOS uses Core Location and its background location indicator.
- The interval is a sampling/upload target. Operating-system scheduling, permission denial,
  unavailable GPS, network loss, or process termination can leave gaps; missing samples are
  never invented or replayed as current. Physical-device background behavior still needs validation.
- With proof enabled, manual stop, NFC stop, building switch, and timeout resolution require
  a new camera capture. There is no gallery picker. Cancelling leaves the shift unfinished.
- The server creates a ten-minute challenge before capture. A bounded JPEG is uploaded,
  then the worker closes/resolves the shift using its proof ID. Upload and close require
  connectivity. The native camera-only flow prevents gallery selection in the supported apps;
  a custom API client cannot be cryptographically proven to have used a camera.
- A known proof-disabled shift keeps existing offline close behavior. A shift never synced
  to the server must connect before finishing, because its authoritative policy is unknown.
- Automatic eight-hour closure still runs without a photo; subsequent worker resolution
  requires a photo for a proof-enabled shift. Existing administrative correction remains available.

## Storage and integration

Migration `028_shift_evidence.sql` adds tenant-scoped policy, coordinates and a bounded
photo per shift in PostgreSQL, plus policy snapshot/proof fields on shifts. No new dependency,
object store, server, ORM or router is introduced. Photo reads are authenticated, `no-store`
and `nosniff`; photo/coordinate fields are redacted in all four telemetry scrubbers.

GET `/shift-policy` exposes current policy to workers; GET/PUT `/admin/shift-policy` manages it.
POST `/shifts/:client_uuid/locations`, `/proof-challenge`, and `/proof` accept evidence.
Existing close/resolve requests accept `proof_id`. Admin evidence endpoints remain tenant scoped.
See `server/check-shift-evidence.js` for the executable API contract and hostile-input cases.

## Verification status

The web build, typecheck, Biome, translation parity and existing web checks passed locally.
Server integration checks used a throwaway PostgreSQL schema and authenticated HTTP requests.
Branding checks passed with no TODO lines. Dedicated feature and review reports supplement this file.
The local admin browser flow saved/reloaded both settings, rejected an invalid interval,
and displayed recorded coordinates and the camera photo. Android emulator checks verified
background samples spaced 60.098 seconds apart, camera cancellation/retake/completion,
and recovery after a committed close response was deliberately lost. These are emulator
results, not physical-device validation. Full executed and unexecuted matrices are recorded in
`shift-location-verification.md`, `shift-proof-verification.md` and
`shift-evidence-web-verification.md` beside this report.
Android debug compilation passed after the two review corrections. The legacy API suite has
one failing adopted-serial/name uniqueness assertion (`200 !== 409`); running the original
`41925c9` server and ops files against a separate test schema reproduces exactly the same
single failure. The new evidence integration suite passes independently.

iOS has **not** been compiled or driven: this Windows host has no Swift/Xcode/iOS simulator.
The mandatory native gate returned:

    checks: swift not found. Install Xcode or the Command Line Tools.

The unexecuted iOS action matrix is in
`NFCTimeSheets/checks/shift-evidence-verification.md`. The entitlement and `project.pbxproj`
are unchanged; confirm background location mode and run the matrix on the owner's Mac/iPhone
before shipping. Do not interpret static iOS checks as a verified native release.
