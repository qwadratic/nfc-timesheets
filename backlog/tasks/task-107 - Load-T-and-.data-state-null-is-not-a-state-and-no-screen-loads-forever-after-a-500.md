---
id: TASK-107
title: >-
  Load<T> and .data-state: null is not a state, and no screen loads forever
  after a 500
status: To Do
assignee: []
created_date: '2026-08-12 06:09'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - web
  - a11y
milestone: m-5
dependencies:
  - TASK-106
documentation:
  - backlog/docs/IA-AND-JTBD.md
  - backlog/docs/DESIGN-SYSTEM.md
  - backlog/docs/UX-AUDIT.md
modified_files:
  - web/lib/api.ts
priority: high
ordinal: 1500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT findings 1 and 8. DESIGN-SYSTEM 6.1. IA-AND-JTBD section 6. The single highest-value
UI change on the board: finding 1 is on every screen and therefore in every job.

WHAT IS WRONG: app/page.tsx:184 and its eleven siblings render the error line AND "Wird geladen..."
forever, with no retry control. docs/media/states/dashboard-error-500-1280.png. The cause is that
loading is expressed as data === null, so error and loading are not mutually exclusive.
Separately, an empty database renders as "Nichts zu tun" plus three vacuous all-clears
(dashboard-empty-1280.png) - the landing page lies to a new director.

THE FIX IS STRUCTURAL, NOT COPY:
    type Load<T> = { k: "loading" } | { k: "ready"; v: T } | { k: "error"; e: string; retry: () => void }
null is not a state. Once the union exists, "loading AND error" stops being representable.

.data-state renders exactly one of four, never two:
    loading | empty-nothing (there is genuinely nothing) | empty-filtered (a filter hid it) | error+retry
empty-nothing and empty-filtered are DIFFERENT COMPONENTS and are never interchangeable: one says
"leg das erste Objekt an", the other says "der Filter zeigt nichts - Filter zuruecksetzen".
An empty database must never read as an all-clear.

SCOPE: all eleven admin screens. This is a wide, shallow change - budget accordingly.

MUST NOT REGRESS: decision-29 phone layout; German is the default locale and en/de key parity stays
exact; the retry control is a real button, keyboard reachable, >= 44px at 390px.

SEQUENTIAL after TASK-106 (needs the .data-state CSS and the tokens).
PARALLEL with TASK-104, 105, 111, 112 once 106 has landed. Do NOT run alongside TASK-108/110 -
all three edit page-level TSX on the same screens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Load<T> (or an equivalent three-case union) replaces every data === null loading test in web/app/**; grep proves zero remaining
- [ ] #2 V2: a forced 500 fixture on all eleven screens renders the error state and the "Wird geladen" node is ABSENT. Restoring the data === null branch makes the check RED
- [ ] #3 V3: every screens error state contains an ENABLED retry control, asserted on all eleven, not one. Removing one retry button -> RED
- [ ] #4 empty-nothing and empty-filtered are separate components with separate strings; a check asserts a filtered-to-zero table never renders the empty-nothing copy
- [ ] #5 The dashboard on an empty database no longer prints an all-clear: assert the three vacuous all-clear strings are absent when counts are zero
- [ ] #6 Evidence: refreshed docs/media/states/ frames for error-500 and empty on the dashboard plus two other screens, at 1280px and 390px
- [ ] #7 Mutation RED output for V2 and V3 pasted into the notes
<!-- AC:END -->
