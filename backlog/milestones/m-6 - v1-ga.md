---
id: m-6
title: v1 GA
status: planned
created_date: '2026-08-12'
---

Milestone: v1 GA

## What this milestone means

The system can be installed for a cleaning company that is not this one, by someone
who is not the author, without code changes. Deferred behind m-5 on 2026-08-12: there
is no point selling a second install while the first one is still unproven.

## Exit criteria

- [ ] Play Console listing live (privacy policy URL, data safety form, content rating).
- [ ] `assetlinks.json` carries BOTH SHA-256 fingerprints (upload key AND Play App
      Signing key) — with only one, App Links stay unverified and every tag tap opens
      a browser.
- [ ] GDPR: privacy policy served, erasure path implemented, retention policy stated,
      `PrivacyInfo.xcprivacy` present, DPA signed with the VM host.
- [ ] CI green on every push, with DB-backed checks failing (not skipping) when no
      database is reachable.
- [ ] A staging environment exists; migrations and payroll arithmetic are proven there
      before production.
- [ ] Deploy writes a build id, keeps the previous release, and can roll back with one
      command.
- [ ] `CHANGELOG.md` (developer) and a German `RELEASES.md` (director) exist and are
      current.
- [ ] A second operator can be onboarded from `ops/branding.json` alone, per
      `ops/REBRAND.md`, with no source edits.
