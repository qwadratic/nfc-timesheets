---
id: TASK-70
title: 'Location access instructions: how does a worker actually get in'
status: To Do
assignee: []
created_date: '2026-08-12 05:45'
labels:
  - design
  - web
  - ux
  - server
  - i18n
milestone: m-6
dependencies: []
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: medium
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md 1.2 names this as the single largest cause of a wasted trip, and the field most often skipped. It is also the one piece of the dispatch design that pays off with ZERO dispatch machinery: a cleaner sent to a building today has the same problem, and the answer currently lives in the director's head or a WhatsApp thread.

SHAPE. One field on locations, shown wherever a worker is told to go to that building.
  * locations.access_note TEXT NULL - free text, the director's own words. Key, door code,
    concierge and their hours, 'Tag rechts neben der Tuer', 'bei Frau K. laeuten'.
  * shown in the admin panel on the building form, and to the worker before they set off.
  * German first (decision-8).

DELIBERATELY NOT: a structured access model (key/code/concierge as separate typed fields).
ponytail: free text is right until the same three shapes appear repeatedly across >20
buildings. Upgrade path is a nullable access_kind column added later; nothing here blocks it.

SECURITY. A door code is a physical-access secret. It must NOT appear in the client portal
(routes/portal.js keeps a deliberately minimal disclosure boundary), must not be logged, and
must not be rendered into any demo recording or screenshot. Worker-visible and admin-visible
only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 locations.access_note added as an additive nullable migration
- [ ] #2 editable on the building form in the admin panel, labelled in German, marked optional
- [ ] #3 visible to a worker assigned to that building, and to nobody else
- [ ] #4 a test asserts the client portal response for a location does NOT contain access_note, and goes RED if the field is added to the portal projection
- [ ] #5 de.json and en.json key parity holds; no bare JSX literals; renders as a labelled card below 768px
<!-- AC:END -->
