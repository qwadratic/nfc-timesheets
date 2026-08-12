---
id: TASK-106
title: >-
  globals.css foundation: tokens, --border-strong, the overflow-wrap fix,
  numeric density, reduced motion
status: To Do
assignee: []
created_date: '2026-08-12 06:08'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - web
  - a11y
  - design
milestone: m-5
dependencies: []
documentation:
  - backlog/docs/DESIGN-SYSTEM.md
  - backlog/docs/UX-AUDIT.md
modified_files:
  - web/app/globals.css
  - web/components/ResponsiveTableLabels.tsx
priority: high
ordinal: 1300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DESIGN-SYSTEM section 12 steps 1-5, plus its three checks in section 11. Closes UX-AUDIT
findings 3 and 7 and one WCAG failure. ONE CSS commit - this is deliberately a single task because
web/app/globals.css cannot survive concurrent editors.

JOB: every job. This is the floor the other UI tasks stand on.

CONTENT:
  1. token block in :root - 6 type sizes (12px floor, was 8 ad-hoc), 6-step 4px space scale plus
     the --row-y density pair, semantic colour names only (no hue names), 4 radii, 3 elevations.
     Old token names stay as aliases for exactly one commit; renaming ~200 usages is a separate diff.
  2. --border-strong #868d97 (3.35:1). Today an inputs only boundary is #d8dce3 at 1.38:1, which
     fails WCAG 1.4.11 non-text contrast. This is the load-bearing new token.
  3. overflow-wrap: anywhere -> break-word + hyphens: auto (globals.css:360). anywhere survives ONLY
     inside the .code-inline/.code-block rule. Measured cost of the bug: five text columns on
     /workers/ at 1280px total 275px where they should total 537px - 1.95x crush, headers render
     vertically.
  4. tabular-nums on ALL money and hours, not just .col-numeric; nbsp before EUR; reserved widths
     --col-money 11ch, --col-hours 6ch, --col-pct 7ch so a cell is the same width for an em dash
     and for 121.334,00 EUR.
  5. shadow ONLY on overlays - never a card, a button or an input.
  6. prefers-reduced-motion: one global !important off-switch replacing the stale two-selector list.
     Motion tier is 120/160ms, opacity and transform only, <=8px travel. NEVER animate: numbers,
     row changes, error appearance, badge state, focus rings.
  7. tfoot gets data-label - ResponsiveTableLabels.tsx:25 walks tbody only, so the mobile totals row
     is four unlabelled numbers (finding 7, pl-populated-flagged-390.png). ~15 lines.

MUST NOT REGRESS: decision-29 - the panel works on a phone; tables become labelled cards below
768px. No sideways scroll at 390px (verified clean today). No sub-44px touch target at 390px
(verified clean today). data-label coverage stays 791/791 on tbody. ResponsiveTableLabels perf
stays in the measured 146->383ms band at 2000 rows.

SEQUENTIAL: nothing else may touch globals.css while this is open. TASK-106, 108, 109 all depend
on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 web/scripts/check-design-tokens.mjs exists, node stdlib only, no new dependency, wired into pnpm verify
- [ ] #2 Check rule: every #hex in globals.css appears inside :root - RED on todays file by construction (#a4262c, #fdf0d5, #5b3a9b, #17457f and six more live inside rules)
- [ ] #3 Check recomputes WCAG contrast for the pinned pairs and asserts text >= 4.5 and control boundary >= 3.0 - it must not trust the table in the doc
- [ ] #4 Check asserts overflow-wrap: anywhere appears only in the code chip rule, and that no transition/animation targets a property other than opacity or transform
- [ ] #5 Mutation proof recorded: --ink-muted #9aa1ab -> RED; --border-strong #d8dce3 -> RED; one hex moved into a rule -> RED; restore -> GREEN. Paste the RED output
- [ ] #6 Column-crush regression check: the five text columns on /workers/ at 1280px measure > 450px combined. RED before the fix (275px), GREEN after
- [ ] #7 tfoot data-label coverage check asserts > 0 labelled cells on /pl/ and /payroll/; deleting the tfoot loop makes it RED
- [ ] #8 Evidence: rebuilt bundle, screenshots at 1280px and 390px of /workers/ and /pl/ replacing the stale ones in docs/media/states/. Nothing in DESIGN-SYSTEM.md has ever been rendered - this task is where that stops
<!-- AC:END -->
