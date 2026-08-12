
## Project: NFC TimeSheets

NFC-based shift tracking for a Vienna cleaning company. Workers tap NFC tags at building entrances to clock in/out. Admin manages workers, locations, and reviews hours/payroll.

### Architecture

- **iOS app** (`NFCTimeSheets/`): SwiftUI + SwiftData. Background NFC via universal links — the
  app never opens an in-app NFC reader (removed in `e4ac6e2`, App Store error 90778).
  TestFlight distribution.
- **Android app** (`android/`): Kotlin + Compose. Worker identity via admin-issued enrolment
  code (decision-26). Signed; not yet on a Play track (decision-27).
- **Server** (`server/`): Node.js REST API on exe.dev VM (`timesheets.exe.xyz`). Postgres 16.
  **systemd** unit `nfc-api` running as the unprivileged `app` user (decision-18 — PM2 is gone).
- **Web admin** (`web/`): Next.js App Router, pnpm, Biome, TypeScript. **Responsive — works on a
  phone** (decision-29). Static export served by the same Node process.
- **AASA + landing** page served from the same Node server at `/.well-known/apple-app-site-association` and `/t`.

### Key files

- `NFCTimeSheets/NFCTimeSheets/ContentView.swift` — main app UI
- `NFCTimeSheets/NFCTimeSheets/API.swift` — API layer (and the `APP_KEY` literal)
- `NFCTimeSheets/NFCTimeSheets/Auth.swift` — Sign in with Apple (decision-22)
- `NFCTimeSheets/NFCTimeSheets/TagLink.swift` — parses `?l=<uuid>` from the tag URL
- `NFCTimeSheets/NFCTimeSheets/TapInbox.swift` — tap intake / cold-launch handling
- `NFCTimeSheets/NFCTimeSheets/NFCTimeSheetsApp.swift` — SwiftData models (Shift, Site)
- `server/server.js` — REST API entry; `server/routes/`, `server/lib/` — handlers and logic
- `APPS-101.md` — original NFC roadmap (reference)
- `Backlog.md` — **FROZEN 2026-07-28 snapshot, contradicts current decisions — do not build
  from it.** Canonical backlog is `backlog/tasks/`.
- `state.md` — pointer only; `README.md` is the live status
- `backlog/decisions/` — architectural decision records (ADRs)

### Apple Developer

**Source of truth is `ops/branding.json`, not this list** (decision-24). The values below are a
convenience copy; if they ever disagree with `branding.json`, `branding.json` wins and
`node ops/check-branding.mjs` is what says so. Shipping under a different signing identity:
`ops/REBRAND.md`.

- Team ID: `6Y842FE8Q4`
- Bundle ID: `io.github.qwadratic.NFCTimeSheets`
- TestFlight: active, internal track
- Associated Domains: `applinks:timesheets.exe.xyz` (literal in the entitlement on purpose —
  templating it makes an unconfigured build emit `applinks:` and kills universal links)

### Hosting

- **API + DB**: exe.dev VM `timesheets.exe.xyz` (SSH: `ssh timesheets.exe.xyz`). **systemd** + Postgres on localhost. No Docker (decision-1); systemd replaced PM2 (decision-18). Supabase is deferred, not rejected (decision-16).
- **Frontend**: static Next.js export served by the same Node API process (decision-16). NOT Vercel — decision-11 is superseded. Cloudflare Pages (decision-14) is deferred.
- **AASA**: served by the API process from generated, committed well-known files
  (`ops/gen-wellknown.mjs`, gated by `server/wellknown/verify.sh` — decision-24)
- Auto TLS via the exe.dev proxy. **One origin** serves both the API and the panel (decision-16)

### Workflow Review Gate

When executing tasks via workflows, the decision compliance check is a **dedicated review agent** that runs AFTER all implementation tasks complete — NOT inside each task. The review gate agent:

1. Reads ALL files in `backlog/decisions/` (use `ls backlog/decisions/` then read each)
2. Reads all code changes produced by the implementation tasks
3. Verifies no new code contradicts any accepted decision
4. Checks code quality: style consistency, duplication, error handling
5. Reports violations with decision ID + offending code
6. BLOCKS completion if violations found

Each implementation task should be formulated to unambiguously specify HOW to implement with regards to decisions. But the review gate is the safety net.

Decision checklist (keep updated as decisions are added):

- No Docker (decision-1)
- Postgres for persistence (decision-2)
- Next.js + pnpm + Biome, no ESLint/Prettier (decision-3)
- AASA on exe.xyz (decision-4)
- NFC location = URI-encoded ID (decision-5)
- Material costs pro-rata by labor hours (decision-6)
- ~~Web admin desktop-only + mobile blocker~~ (decision-7) — **SUPERSEDED by decision-29**
- All strings externalized for i18n (decision-8)
- npm versions pinned exact (decision-9)
- 8h shift auto-timeout + mandatory resolution (decision-10)
- ~~Frontend on Vercel~~ (decision-11) — SUPERSEDED by decision-16
- Supabase (decision-12) DEFERRED and its free-tier risk (decision-13) MOOTED by decision-16
- Cloudflare Pages for the admin panel (decision-14) DEFERRED by decision-16
- Tag hostname stays `timesheets.exe.xyz`, tags left unlocked (decision-15)
- Everything server-side on the one exe.dev VM; no framework, no ORM, no router (decision-16)
- next-intl, English messages for MVP (decision-17)
- systemd, not PM2 (decision-18)
- Shift posted at clock-IN; server is authoritative for open shifts (decision-19)
- Web admin uses email + password; the admin PIN is gone (decision-20)
- Tag URI carries the location UUID, never the slug (decision-21)
- Worker identity via Sign in with Apple; identity comes from the session, never the body (decision-22)
- Sentry on API + iOS; server deps are now `pg` + `@sentry/node` and nothing else. Telemetry
  must never be required to boot and must never block a clock-in (decision-23, amends decision-16)
- Operator identity is configuration: `ops/branding.json` is the single source, the well-known
  files are generated (`ops/gen-wellknown.mjs`) and committed, the AASA appID list is
  append-only, the iOS entitlement stays a checked literal, and `ops/check-branding.mjs` +
  `server/wellknown/verify.sh` are the gates (decision-24)
- decision-25 is a TOMBSTONE — the number was never used. Do not reuse it (decision-27 cites it)
- Android worker identity via an admin-issued, single-use enrolment code — NOT a third-party
  sign-in provider (decision-26)
- Google Play developer account is PERSONAL; Android ships on the internal testing track
  (decision-27)
- ~~Contract history ships, worker rate history does not~~ (decision-28) — **SUPERSEDED by
  decision-30**
- The admin panel works on a phone; the mobile blocker and `DesktopOnlyGuard` are gone
  (decision-29, supersedes decision-7)
- Worker rate history (`worker_rates`) AND an audit trail on every money edit (`shift_edits`,
  `worker_rate_changes`). Payroll and the reports resolve the rate from the SAME source.
  Rate changes are "raise" (forward-dated) or "correction" (retroactive, reason required)
  (decision-30, supersedes decision-28)

Decisions can only be changed by creating a new decision record that supersedes the old one.

**This checklist is load-bearing and it went stale for eight days.** It stopped at decision-24
while 26–29 were binding, so agents reading it treated the reversed mobile blocker as current.
Updating this list is a required step of writing any new decision record.

### i18n

German is the shipped default. `web/messages/de.json` (60 KB) and `en.json` (54 KB) are both
complete real translations — not placeholders — and `pnpm check` enforces key parity between
them. No hardcoded user-visible strings.

### Dependencies

- Pin all npm versions exact (no `^` or `~`)
- `.npmrc` must have `save-exact=true`
- Prefer latest stable minus one minor for major deps
- Use pnpm, never npm or yarn

<!-- BACKLOG.MD GUIDELINES START -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**For every user request in this project, run `backlog instructions overview` before answering or taking action.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Use the detailed guides when needed:
- `backlog instructions task-creation` for creating or splitting tasks
- `backlog instructions task-execution` for planning and implementation workflow
- `backlog instructions task-finalization` for completion and handoff

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
