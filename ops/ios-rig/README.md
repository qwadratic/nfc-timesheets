# ops/ios-rig - local verification rig for the iOS WORKER flows (TASK-365.22)

A real server, a real database, real TLS and a real simulator, all on `127.0.0.1`, so the
worker flows of the iOS app can be DRIVEN (not read from source) and the server's rows and the
wire can be asked what happened. Nothing here is a product mode: no demo mode, no no-NFC mode,
no change to `NFCTimeSheets/`, `server/` or the entitlements.

```
export RIG_HOME=<an absolute directory OUTSIDE the repo>     # keys, cluster, logs, screenshots
ops/ios-rig/up.sh            # ~25 s: Postgres + API + TLS front + simulator clone + codes
ops/ios-rig/rig.sh build     # the app, built against 127.0.0.1:8444 (incremental)
ops/ios-rig/walk.sh list     # the walks
ops/ios-rig/walk.sh p2       # a phase (p1 p2 p3 p4 p5 p6 bug), or one walk, or `all`
ops/ios-rig/down.sh          # processes, cluster, CA + keys, codes, simulator clone: gone
ops/ios-rig/down.sh --purge  # ... and DerivedData, the wire log, screenshots
```

## What `up.sh` starts

| Piece | Where | Notes |
|---|---|---|
| Postgres 18 (Homebrew `initdb`/`pg_ctl`) | `127.0.0.1:5433`, no unix socket | scram-sha-256, throwaway passwords in `$RIG_HOME/secrets.env` (0600), `fsync=off` |
| app role `rig_api` | same cluster | `NOSUPERUSER NOBYPASSRLS` - `server/lib/db.js` refuses anything else, so the REAL row-level security runs |
| the server's migrations | `server/db/migrate.js` | all 26 files, applied as the cluster superuser |
| seed | `seed.sql` | company "Rig Reinigung GmbH"; buildings Alpha (zones Stiege 1 verified, Keller UNVERIFIED, Dachboden verified/deactivatable) and Beta (Haupteingang verified); workers Anna Rig (A) and Bernd Rig (B); operator Olga |
| API | `127.0.0.1:8082` via `serve.mjs` | `server/server.js`'s own `createServer()`, bound to loopback (server.js's own boot listens on every interface). Third-party env (`SENTRY_*`, `TWILIO_*`, `RESEND_*`, `GOOGLE_*`, ...) is stripped by prefix |
| TLS front | `127.0.0.1:8444` via `front.mjs` | throwaway CA + server certificate (7 days) trusted by the simulator clone; JSONL wire log; fault injection from `$RIG_HOME/run/faults.json` |
| simulator | a CLONE of "iPhone 17 Pro" (`RIG_SIM_SOURCE`) | the original and every other device are never touched; the clone, and the CA in its keychain, are deleted by `down.sh` |
| codes | `$RIG_HOME/codes.env` (0600) | one fresh 5-digit enrolment code per worker, 14 minute life, single use: `rig.sh new-code A|B` |

Ports can be moved with `RIG_API_PORT`, `RIG_FRONT_PORT`, `RIG_PG_PORT`. The build settings
`TS_API_HOST` / `TS_TAG_HOST` carry the front's address exactly as
`FinishReportedCardUITests.swift` documents; `rig.sh build` prints the `Info.plist` values it
produced.

### The one constant that is not generated

The shipped app sends a compiled-in `X-App-Key` (`API.appKey`, committed in cleartext on
purpose) and the product may not change for the rig, so the loopback server has to accept
exactly that constant. `lib.sh` reads it out of `API.swift` at start-up and hands it to the
API process by environment only; it is never written to `$RIG_HOME`. Every OTHER secret
(database passwords, CA key, server key, enrolment codes, session tokens) is generated per rig.

## Files

| File | Job |
|---|---|
| `up.sh` / `down.sh` | bring the rig up / take it down and leave nothing behind (each external call is wrapped in a timeout) |
| `rig.sh` | state flips and reads: `zone`, `zone-add`, `building`, `schedule-set`, `shift-open-elsewhere`, `revoke-sessions`, `server-stop/start`, `net-down/up`, `fault`, `wire-*`, `new-code`, `reset-data`, `shifts`, `sim-uninstall`, `sim-shot`, `build`, `test` |
| `walk.sh` | the DRIVERS: set state, run one XCUITest, flip state at the test's named rendezvous points, then assert on the database and the wire |
| `seed.sql`, `serve.mjs`, `front.mjs`, `wire.mjs`, `lib.sh` | the pieces above |
| `NFCTimeSheets/NFCTimeSheetsUITests/WorkerRig*.swift` | the XCUITests: `WorkerRigSupport` (sign-in through the REAL code form, rendezvous, screenshots), `...SignIn`, `...ManualStart` (P2), `...SharedPhone` (P3 + P6 device-wide), `...Schedule` (P4), `...Delivery` (P5, P6), `...Zones` (P1 + two defect probes) |

## How a walk works

1. `fresh_phone`: app uninstalled from the clone, data reset, faults cleared, fresh codes.
2. The test runs ONE scenario (`xcodebuild test-without-building -only-testing:`), with
   `TEST_RUNNER_TS_RIG_*` carrying the code, the seed's zone uuids, the screenshot directory
   and the sync directory. The code is never in a test's source.
3. At a rendezvous (`Rig.rendezvous("net-down")`) the test stops and the driver flips server
   state; the name of the rendezvous IS the flip (`flip()` in `walk.sh`).
4. After the test the driver asks Postgres and the wire log what really happened. Every line is
   `PASS` or `FAIL` with the observed value; nothing ticks a backlog criterion automatically.

Taps use the DEBUG-only `--ts-demo --ts-demo-tap <zone uuid>` launch argument that already
existed (a simulator has no NFC radio). Signing in does not.

"Server down" has two honest shapes: `server-stop` kills the API (the front answers 502) and
`net-down` stops the front (the phone's connection is REFUSED: status 0, the "No connection"
sentence). `fault set` makes the front answer a given status for a path (used for "a server
WITHOUT the route", a held slow answer, and a `GET /auth/session` that answers another worker).

## What the rig proves

- the real server (real RLS, real validation, real refusals 422/409/401) and the real phone
  code agree on the matrix rows listed in the backlog notes of TASK-365.2 .. .7;
- what a request carried (`body.location_uuid`, `manual`, `auto_closed`) because the wire is
  logged, and what the server stored because Postgres is asked;
- what the phone SHOWS (accessibility tree + screenshots under `$RIG_HOME/shots`).

## What it cannot prove

- **NFC.** There is no radio; the tap is injected after the URL parse (see `DemoHooks.swift`).
  Universal-link launch, background tag read and the Core NFC sheet are untested here.
- **Out-of-app signals.** The home-screen badge is not queryable on this Simulator (the icon's
  accessibility label never carries it and the static grid never drew it in ~17 screenshots),
  pending/delivered local notifications have no out-of-process reader, and Live Activities have
  no widget target. Criteria that name the badge, the reminder ladder or a Live Activity are
  left open for a device.
- **VoiceOver.** The spoken label is read from the accessibility tree; VoiceOver itself is not
  run (focus order and announcements are not observed).
- **A real phone's network.** Offline is a refused connection or a 502 from the front, not a
  captive portal, a lossy cell link or an iOS "low data" mode.
- **Time.** A shift older than 8 hours that is also UNACKNOWLEDGED cannot be produced (no UI
  path writes a back-dated local row); the "overdue beats pending" precedence is the Foundation
  check's, and only the "Over 8 hours" rendering of an adopted 9 h-old shift is driven.
- **The auto-close timer, SMS, e-mail, Apple/Google/Sentry services.** Not running, not
  reachable, by design.

## Troubleshooting seen while building it

- `postmaster became multithreaded during startup` - `LC_ALL` must name a real locale (lib.sh sets it).
- `xcodebuild` shuts the clone down after a test run; `rig.sh` boots it again before any
  `simctl` call on the app container.
- Killing the app in the FOREGROUND right after sign-in loses the session cookie (the next
  launch's first call is a 401). The harness goes Home and waits ten seconds before it kills.
- The idle list is lazy: "Start without a tag" is below the fold when rows are on screen, so
  the idle check is the navigation title `TimeSheet`.
