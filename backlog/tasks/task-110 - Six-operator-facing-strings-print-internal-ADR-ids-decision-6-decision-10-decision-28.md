---
id: TASK-110
title: >-
  Six operator-facing strings print internal ADR ids - decision-6, decision-10,
  decision-28
status: To Do
assignee: []
created_date: '2026-08-12 06:10'
updated_date: '2026-08-12 06:14'
labels:
  - ux
  - i18n
  - web
milestone: m-5
dependencies: []
documentation:
  - backlog/docs/UX-AUDIT.md
modified_files:
  - web/messages/de.json
  - web/messages/en.json
priority: high
ordinal: 1400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UX-AUDIT finding 10. A Viennese cleaning-company director has no way to resolve "decision-6".
It reads as an error code and invites a support call about a sentence that is otherwise well written.

THE SIX KEYS, in BOTH locales:
    materials.noteAttribution      materials.locationHint       pl.methodMaterials
    pl.methodExclusions            contracts.noteLabourNoHistory  analytics.noteExclusions
Frames: pl-populated-flagged-1280.png, contracts-history-open-1280.png,
analytics-map-nokey-1280.png, materials-populated-1280.png.

FIX: say the rule, not its filename. "verteilt (decision-6)" -> "anteilig nach Arbeitsstunden
verteilt". "unberuecksichtigt (decision-10)" -> "nicht geklaerte automatisch beendete Schichten
bleiben unberuecksichtigt". The ADR id belongs in a code comment next to the string, where the
next developer needs it, and nowhere a director can see it.

JOB: every reporting job. Trust is the product here.

MUST NOT REGRESS: the meaning. Each rewritten sentence must still state the same rule the ADR
states - this is a copy change, not a policy change. de/en parity stays exact.

SEQUENTIAL with TASK-104 and TASK-109 - shared messages files.
LOW EFFORT, HIGH CONSEQUENCE: do it in the first wave.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A check greps web/messages/*.json for /decision-\d+/ and fails on any match - RED today on six keys in two locales
- [ ] #2 Each of the six rewritten strings still states the rule its ADR states; the ADR id moved to a code comment beside the string
- [ ] #3 de/en key parity exact; both locales rewritten, not just German
- [ ] #4 Evidence: refreshed pl-populated-flagged-1280.png and materials-populated-1280.png
<!-- AC:END -->
