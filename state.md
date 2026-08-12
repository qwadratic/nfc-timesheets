# NFC TimeSheets — Project State

> **This file is a pointer, not a source of truth.**
>
> It used to be a snapshot, and on 2026-08-12 a backlog audit found that every substantive
> claim in it had been false for roughly two weeks: it said "Not deployed" while the system
> was live and in daily use, "PM2" after decision-18 replaced it with systemd, "Android:
> research only" after a signed Android build had been field-tested, and "Backlog.md — 20
> tasks" while the canonical board held 53.
>
> A snapshot that nobody updates is worse than no snapshot, because agents and humans both
> read it as current. So it no longer holds state. It tells you where state actually lives.

## Where the truth is

| Question | Authoritative source |
|---|---|
| What works today, what is broken | `README.md` — sections "Working today" and "Things that will bite you" |
| What is binding architecture | `backlog/decisions/` (30 records) + the checklist in `AGENTS.md` |
| What is being built, and its status | `backlog/tasks/` via `backlog task list --plain` |
| What "done" means for this phase | `backlog/milestones/m-5 - vienna-pilot.md` |
| Operator identity, branding, signing | `ops/branding.json` (decision-24) — never a copy in prose |
| How to run, deploy, restore | `README.md`, `ops/README.md`, `server/README.md` |

## Current phase

**m-5 Vienna Pilot** — make the one existing Vienna customer reliable. Play Store listing,
white-label, CI, and staging are explicitly deferred to **m-6 v1 GA**. Exit criteria for both
are written in the milestone files, not here.

## Standing facts that are cheap to get wrong

These are duplicated from `ops/branding.json` and `backlog/decisions/` for reading convenience.
**If they ever disagree with the source, the source wins** and `node ops/check-branding.mjs`
is what says so.

- Apple Developer Team `6Y842FE8Q4`; bundle `io.github.qwadratic.NFCTimeSheets`
- Server: `timesheets.exe.xyz` (exe.dev), Node 22 + Postgres 16, systemd unit `nfc-api` as the
  unprivileged `app` user
- Admin auth is email + password against the `admins` table (decision-20). There is no ADMIN_PIN
- Tag URI is `https://timesheets.exe.xyz/t?l=<LOCATION_UUID>` — the UUID, never the slug
  (decision-21), and never the hardware UID (decision-5)
- Never write a live secret into this file. `legacy-backup/` and `.vm-legacy-backup/` are
  gitignored for exactly that reason

## Known-untrue-elsewhere

`Backlog.md` at the repo root is a **frozen 2026-07-28 snapshot** that contradicts decisions
10, 18, 20, 21 and 29 in fourteen places. It is kept for history. Do not build from it.
