---
id: TASK-100
title: >-
  Insight of the day: nightly, deterministic choice, numeral-set verifier,
  Nachrechnen link
status: To Do
assignee: []
created_date: '2026-08-12 06:04'
labels:
  - assistant
  - web
dependencies:
  - TASK-96
  - TASK-99
references:
  - backlog/decisions/decision-36.md
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE GOVERNING RULE: the model never computes a number. It phrases a number that SQL computed.
An assistant confidently wrong about money is worse than no assistant.

nfc-assistant-insight.timer at 04:15 Vienna — after the 04:00 pg_dump, modelled on the existing
nfc-autoclose.timer (decision-18). No new supervision mechanism, no cron, no queue.

1. Run ~6 fixed hand-written aggregates: hours by building this week vs the trailing 8-week mean;
   unresolved auto_closed count; material requests open > 3 days; buildings with no contract price;
   workers with shifts last month and none this month; largest week-on-week move.
2. Pick the largest standardised deviation. THIS CHOICE IS DETERMINISTIC — the model does not choose
   what is interesting, because 'interesting' applied to payroll is where an assistant invents a story.
3. Hand the model the chosen fact as structured values; ask for ONE German sentence.
4. Verify (§7.1) and store one assistant_insight row per tenant per day.

Numeral-set verifier: every numeral in the sentence must have been handed to it, and none handed to
it may be missing. Failure is NOT an error message to the director — it is a silent fall back to the
deterministic template sentence, plus a Sentry event for us. A card saying 'Assistent-Fehler' is
worse than a card saying the plain fact plainly.

Rendering on /: one card, and EVERY card carries a 'Nachrechnen' link to the ABSOLUTE-range URL
(from/to, never period — IA doc §3.1) that produced it. An insight you cannot click through to the
rows is a rumour. Suppressed entirely when the underlying set is empty (IA doc §6 rule 1: never
assert an all-clear over an empty set).

Also in this task, the narrow banner (design doc §7.3): type chosen deterministically from a fixed
list, model writes only the wording, NEVER on /payroll/ or /reports/, only checkable claims,
aria-live='polite' never assertive, dismissal sticks 7 days per type.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V6: stub the provider to alter one digit; the deterministic template renders instead. RED with the verifier removed
- [ ] #2 Page load makes ZERO model calls; / reads one indexed row (shares V11 with TASK-96)
- [ ] #3 Every insight card has a Nachrechnen link using from/to, never period; a test asserts the linked rows reproduce the figure
- [ ] #4 Insight is suppressed, not softened, when the underlying set is empty
- [ ] #5 Banner never renders on /payroll/ or /reports/; aria-live is polite
- [ ] #6 The nightly timer also runs the assistant_audit retention sweep (90 days reads / 7 years mutations)
<!-- AC:END -->
