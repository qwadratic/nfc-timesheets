---
id: TASK-72
title: >-
  GATED: dispatch pricing - a floor from worker_rates, a bounded published
  ladder, and no surge
status: To Do
assignee: []
created_date: '2026-08-12 05:46'
labels:
  - design
  - server
milestone: m-6
dependencies:
  - TASK-55
  - TASK-69
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: low
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md section 3. Taxi-style price discovery that pays workers better while staying bounded, with the failure modes stated rather than wished away.

GATE - DO NOT BUILD THIS YET. Three conditions, ALL required:
  1. TASK-55 shipped (worker_rates, decision-30). The floor is resolved from worker_rates on
     the job's Vienna calendar date. Today workers.hourly_rate_cents is a single mutable
     column, so a job priced in March silently reprices when a raise lands in September -
     decision-30's bug, now attached to a number a person was PAID. The floor is
     un-computable until this exists.
  2. >= 15 active workers WHO DO NOT ALL KNOW EACH OTHER.
  3. >= 20 dispatchable jobs/week.

WHY 2 AND 3 ARE NOT NEGOTIABLE. The defence against 'decline until the price rises' is that
the price step belongs to the JOB, not the person: declining buys a higher price at a much
lower probability, because everyone else sees the higher step first. That mechanism is DEAD at
N=4. And four cleaners in one group chat can decline to the ceiling on every job forever, which
no algorithm distinguishes from a busy Tuesday. At small N, dynamic pricing is theatre.

THE INVARIANTS (JOB-DISPATCH.md 3.1-3.4, with a runnable check already written there):
  floor_cents = ceil((work_min + travel_min) * rate_cents_per_hour / 60)   rounded UP, once
  price(step) = clamp(round(floor * STEP[step]), low=floor,
                      high=min(floor * 1.8, billable_ceiling))
  STEP = [1.00, 1.25, 1.50], published and fixed. MAX_MULT published.
  When billable_ceiling bites, THE MARGIN ABSORBS IT, NEVER THE WORKER - the lower clamp is
  the floor, so a thin-margin job goes to zero/negative margin and gets flagged.
  Worker pay rising must never silently raise the client's invoice.

EXPLICITLY REJECTED: surge/demand/time-of-day multipliers. They invite exactly the gaming
above, they are unexplainable to the person receiving the money, and they turn a pay dispute
into an argument about an algorithm. Fixed published steps or nothing.

WRITE THE DECISION RECORD FIRST. Pricing worker pay by algorithm is a decision of the same
weight as decision-30, and it must be a record before it is code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GATE CHECK recorded before any code: TASK-55 shipped, >= 15 workers, >= 20 jobs/week
- [ ] #2 a decision record exists covering the floor, the published fixed ladder, the two ceilings, and the rejection of surge pricing
- [ ] #3 floor is resolved from worker_rates on the job's Vienna calendar date - the SAME source payroll uses, asserted by a test that compares both paths to the cent
- [ ] #4 the JOB-DISPATCH.md 3.4 invariants ship as a real test: never below floor at any step, bounded above, monotone in step, and a tight billable ceiling clamps the margin and not the worker
- [ ] #5 the test is mutation-proven: ceil->floor in the floor goes RED, and removing the lower clamp goes RED
- [ ] #6 no code path raises a client invoice as a consequence of a worker price step
<!-- AC:END -->
