---
id: TASK-74
title: >-
  GATED: the dispatch health screen - one screen, one boolean, and it must be
  able to be red
status: To Do
assignee: []
created_date: '2026-08-12 05:46'
labels:
  - design
  - ux
  - web
  - i18n
milestone: m-6
dependencies:
  - TASK-69
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: low
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md section 7. The director needs ONE screen answering ONE question: do I need to do something in the next hour. Everything else is analytics and belongs elsewhere.

GATE. Pointless until there are offers to observe - i.e. until TASK-69 is live AND assignment
has waves at all (TASK-72/TASK-73 gates met). Before that the screen has four zeroes and a
green light that can never turn red, which is the exact failure it is designed to avoid.

SHAPE. Phone-legible, ~1080px, no horizontal scroll (decision-29). ASCII sketch in section 7.
  band 1  ANGEBOTEN / VERGEBEN / OFFEN / UEBERFAELLIG - four counts, today, Vienna day
  band 2  median time-to-accept; unqualified draft count + OLDEST AGE
  band 3  fill rate by wave; price-step distribution; top 3 decline reasons
  band 4  GEFAEHRDET - at-risk jobs sorted by time to deadline, ONE action per row

FOUR RULES, each of which is the point:
  * ONE BOOLEAN AT THE TOP AND IT MUST BE ABLE TO BE RED.
    green iff unfilled = 0 AND past_deadline = 0 AND oldest_draft < 4h. The definition is
    printed next to it. A dashboard that is always green is a decoration.
  * EVERY DISTRIBUTION ANSWERS A NAMED MISCONFIGURATION QUESTION.
    mostly wave 3 -> the ranking is wrong. mostly ceiling price -> the floor is too low.
    always 'Weg' as the decline reason -> the zones are wrong. A chart with no such question
    is a chart nobody reads - delete it rather than ship it.
  * NO VANITY METRICS. No cumulative jobs ever, no total revenue. Those are analytics.
  * ONE ACTION PER AT-RISK ROW, on the row. If the director must navigate away to act they
    will use the phone in their other hand and the screen becomes a museum.

VERIFICATION CULTURE. The red state is the load-bearing one. Test it by MAKING it red -
seed a past-deadline job in the demo database (demo/check-guards.sh refuses anything but
nfc_demo) and assert the banner flips. A health indicator whose negative case has never been
observed is not an indicator.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GATE CHECK recorded before any code: TASK-69 live and offer waves exist
- [ ] #2 one screen, one boolean at the top, with its green definition printed beside it
- [ ] #3 the red state is demonstrated against seeded nfc_demo data for each of the three red causes: unfilled, past deadline, stale draft
- [ ] #4 each distribution carries its named misconfiguration question in the UI or is not shipped
- [ ] #5 every at-risk row exposes its action inline; no navigation required to act
- [ ] #6 German default, de.json/en.json exact key parity, no bare JSX literals, labelled cards below 768px
<!-- AC:END -->
