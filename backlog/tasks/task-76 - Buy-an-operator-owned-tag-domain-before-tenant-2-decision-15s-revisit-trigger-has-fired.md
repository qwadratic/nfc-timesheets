---
id: TASK-76
title: >-
  Buy an operator-owned tag domain before tenant #2 - decision-15's revisit
  trigger has fired
status: To Do
assignee: []
created_date: '2026-08-12 05:48'
labels:
  - ops
  - nfc
  - blocked-on-owner
dependencies: []
documentation:
  - backlog/docs/MULTI-TENANCY.md
  - backlog/decisions/decision-32
priority: high
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-15 set its own revisit trigger: move the NFC tag host to an operator-owned domain "before the first paying client, or before tag count exceeds what can be rewritten in one cleaning round". Multi-tenancy (decision-32) is that moment.

Today every tag carries https://timesheets.exe.xyz/t?l=<uuid>. That host is a subdomain of a platform we do not control the DNS for. AASA and assetlinks are host-exact and redirects are NOT followed (decision-4, decision-15), so the host in a tag is permanent for that tag's life.

The window is open exactly as long as the tag count is small. It closes permanently once tags are glued to a SECOND company's walls: a host move then becomes a site visit to every building of every tenant, and the tenants are not ours to walk into.

Cost: ~EUR 10/yr for e.g. app.<operator>.at with a CNAME to the exe.dev VM. That is the entire mitigation.

BLOCKED ON OWNER: buying a domain is a purchase and a DNS change, not an agent action. What an agent CAN do afterwards is the mechanical part - branding.json host, gen-wellknown, verify.sh, the entitlement line per ops/REBRAND.md, and the tag rewrite tooling.

Note the app-release cost honestly: changing the tag host needs a new iOS build (the Associated Domains entitlement is a compiled-in literal by decision-24 section 6) and a new Android build (intent filter). Doing it once now costs one release. Doing it later costs one release PLUS a physical tag rewrite at every building.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision is recorded either way: domain bought (with the name), or explicitly deferred with the accepted consequence written down
- [ ] #2 If bought: DNS CNAME resolves to the VM and the exe.dev proxy serves TLS for it
- [ ] #3 If bought: both well-known files are served from the new host with ZERO redirect hops, verified by curl -sI showing 200 and no Location
- [ ] #4 If bought: ops/branding.json host updated, ops/gen-wellknown.mjs --write run, the committed diff reviewed by a human before any tag is written, node ops/check-branding.mjs green
- [ ] #5 If bought: the entitlement literal is updated per ops/REBRAND.md and a build is confirmed to open the app from a real tap on a real phone before ANY tag is rewritten
<!-- AC:END -->
