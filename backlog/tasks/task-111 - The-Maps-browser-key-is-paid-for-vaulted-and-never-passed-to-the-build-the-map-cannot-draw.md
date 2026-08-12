---
id: TASK-111
title: >-
  The Maps browser key is paid for, vaulted, and never passed to the build - the
  map cannot draw
status: To Do
assignee: []
created_date: '2026-08-12 06:10'
updated_date: '2026-08-12 06:14'
labels:
  - ops
  - web
  - ux
milestone: m-5
dependencies: []
documentation:
  - backlog/docs/UX-AUDIT.md
modified_files:
  - ops/deploy.sh
priority: high
ordinal: 1600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 4. "Provisioned but never installed" - the exact failure pattern the brief names.

    psst list                       -> NEXT_PUBLIC_GOOGLE_MAPS_KEY [browser, vercel]  provisioned
    rg NEXT_PUBLIC ops/deploy.sh    -> only NEXT_PUBLIC_DEFAULT_LOCALE=de             never passed
    grep -rl AIza /srv/nfc/public   -> nothing                                        not in bundle

ops/deploy.sh:44 is the whole build line:
    (cd web && pnpm install --frozen-lockfile && NEXT_PUBLIC_DEFAULT_LOCALE=de pnpm verify)
=> MAPS_API_KEY === "" (web/lib/map.ts:24) forever => mapStatus = "noKey" forever
(analytics/page.tsx:184) => and every Street View thumbnail returns null (web/lib/map.ts:238).

SECOND HALF, separate symptom, same root: production rows still carry geocode_status = no_key.
GOOGLE_GEOCODING_KEY is provisioned AND wired AND on the VM - the rows are simply stale, because
geocoding never re-ran after the key arrived. A backfill run is needed, and it is a WRITE.

JOB: JTBD #10 - where are my buildings. Also the Vienna map on the dashboard (TASK-48, Done).

MUST NOT REGRESS: the honest degradation. When no key is configured the panel must still say so
rather than render a broken tile - that part is currently right and must survive.
The key is restricted (HTTP referrer); confirm the restriction covers timesheets.exe.xyz before
blaming the build. A browser key IS shipped to the client by design - that is not a leak, but it
must still never appear in a commit, only in the build environment.

OWNER GATE: the deploy itself writes to production. Everything up to and including the dry run is
work; the deploy and the geocode backfill need the owners go-ahead.

PARALLEL: yes. Touches ops/deploy.sh only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ops/deploy.sh passes NEXT_PUBLIC_GOOGLE_MAPS_KEY from the psst vault into the web build; the key is never written to a file in the repo
- [ ] #2 A check greps the built bundle for the key prefix and fails when absent - RED against todays /srv/nfc/public by construction
- [ ] #3 After deploy: the Karte panel on /analytics/ draws, and a Street View thumbnail resolves. Frame in docs/media/states/ replacing analytics-map-nokey-1280.png
- [ ] #4 The no-key degradation path still renders its honest message when the variable is unset - proven by one build with it removed
- [ ] #5 OWNER-GATED: geocode backfill re-run so production rows leave geocode_status = no_key. Not run without explicit go-ahead; nfc_demo first
<!-- AC:END -->
