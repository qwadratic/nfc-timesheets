---
id: TASK-82
title: 'Web admin: Bereiche section on the building page, without a tree widget'
status: To Do
assignee: []
created_date: '2026-08-12 05:50'
labels:
  - zones
  - web
  - i18n
  - a11y
dependencies:
  - TASK-80
documentation:
  - backlog/docs/ZONES-AND-TAG-WRITING.md
priority: high
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE RULE: a director who never uses zones sees ONE line of new chrome, forever.

/locations keeps its shape - flat table, WHERE parent_id IS NULL, plus one column 'Bereiche'
showing the count or an em-dash. Em-dash, NOT 0: a zero invites the reading 'you should add
some'.

The building DETAIL page grows one section below the existing fields: a FLAT table of zones.
Not a tree, not an expander, not drag-to-reorder. This is only honest because depth is capped
at 1 in the database (decision-33) - the cap is what buys the flat UI.

```
Bereiche                                              [ + Bereich ]
Stiege A       Flaeche 120,0 m2   Stock EG      Tag +   [Bearbeiten]
Buero 1. OG    Flaeche  85,5 m2   Stock 1. OG   Tag -   [Bearbeiten]
```

Zero zones => heading + one button, nothing else.

Zones appear NOWHERE else: no sidebar entry (a zone is a property of a building, never a
destination), not on the dashboard, payroll or P&L.

Shifts list gets one column 'Bereich' showing the zone name or 'Gebaeude gesamt'. NEVER
'(keine Zone)', never an empty cell, never a warning icon - a building-level shift is a
complete record, not a defect (decision-33 point 4).

German label is 'Bereich', not 'Zone': 'Objekt' is already the building in this panel's
German. 'floor' is TEXT - Austrian floors are EG, 1. OG, Keller, not integers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /locations stays a flat list of buildings with one added 'Bereiche' column; em-dash when none
- [ ] #2 Building detail page has a flat Bereiche table; no tree, expander or nesting anywhere in the DOM
- [ ] #3 Shifts list shows 'Gebaeude gesamt' for building-level shifts - assert the exact string, not merely that the cell is non-empty
- [ ] #4 zones.* keys added to BOTH web/messages/de.json and en.json with EXACT key parity; pnpm check green; no bare JSX literals
- [ ] #5 Mobile (decision-29): the zone table is a .data-table and renders as labelled cards below 768px via components/ResponsiveTableLabels.tsx. Verified by reading the rendered labels at 375px, not by asserting the CSS class exists
- [ ] #6 a11y: Tag status is icon PLUS text, never colour alone; area input is type=number inputmode=decimal with the unit in the visible label (not a placeholder); the zone table has a <caption> naming its building
- [ ] #7 Area input accepts 12,5 and 12.5 and stores 1250 dm2; round-trips back to the same displayed value
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 pnpm check green (Biome, key parity, no hardcoded strings)
- [ ] #2 No new npm dependency
<!-- DOD:END -->
