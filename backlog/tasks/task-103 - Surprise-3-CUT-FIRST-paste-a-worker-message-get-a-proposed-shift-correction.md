---
id: TASK-103
title: >-
  Surprise 3 (CUT FIRST): paste a worker message, get a proposed shift
  correction
status: To Do
assignee: []
created_date: '2026-08-12 06:04'
labels:
  - assistant
dependencies:
  - TASK-98
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: low
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design doc §9.3. FILED WITH ITS OWN ARGUMENT AGAINST IT — this is the one to cut if anything is cut,
and it is deliberately last and low.

What it does: the director pastes 'hab um 6 angefangen, Handy war leer' from WhatsApp into the chat
and gets a TIER-B proposed shift correction with worker, building and times pre-filled, the original
message text mirrored into decision-30's required note field. One capability over the existing
POST /admin/shifts and PATCH /admin/shifts/:id. No write path, no dependency. Serves JTBD-2 and
JTBD-4, and both of those jobs START as a message from a worker.

WHY IT IS THE ONE TO CUT: it is the only assistant feature where the model CREATES data rather than
CHECKING it, and the failure mode is the worst kind — 'um 6' transcribed as 06:00 when the worker
meant 18:00 is plausible, silent, and lands on a payslip. The same job takes twenty seconds in the
manual shift form that already exists, so the saving is convenience, while TASK-101 and TASK-102
remove a class of error. Keep the features that check numbers; cut the one that invents them.

If built anyway, the mitigations are mandatory, not optional:
- ambiguous times (a bare '6' with no AM/PM marker and no context) must be REFUSED, not guessed
- the proposed times are shown next to the pasted text, verbatim, side by side
- the director's reason field stays mandatory and un-prefilled (decision-36 §9)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An ambiguous time is refused with a German sentence, never guessed. A test covers 'um 6', 'um sechs', 'frueh'
- [ ] #2 The pasted text is shown verbatim beside the proposed times
- [ ] #3 The proposal is tier B and goes through TASK-98's approval path unchanged
- [ ] #4 The worker's actual words land in shift_edits.note, not a paraphrase
- [ ] #5 A decision to cut this is recorded in the task rather than silently dropping it
<!-- AC:END -->
