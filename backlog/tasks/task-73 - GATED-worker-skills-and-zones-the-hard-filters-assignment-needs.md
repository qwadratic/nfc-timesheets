---
id: TASK-73
title: 'GATED: worker skills and zones - the hard filters assignment needs'
status: To Do
assignee: []
created_date: '2026-08-12 05:46'
labels:
  - design
  - server
  - web
  - ux
milestone: m-6
dependencies:
  - TASK-69
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: low
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md 2.2: skill and proximity are HARD FILTERS on who may be offered a job, and neither exists. workers has exactly five columns and none of them is a skill; locations has lat/lng and the one production row has lat NULL (TASK-16), so proximity cannot be computed at all.

GATE - DO NOT BUILD THIS YET. Below ~15 active workers the director knows who can do what and
who is near where, and their ranking beats any stored one. This task exists so the gap is
recorded, not so it is filled now. Unlock when TASK-69 is live AND the roster is >= 15.

SHAPE WHEN UNLOCKED.
  * worker_skills(worker_id, job_type) - job_type from the same closed vocabulary the jobs
    table uses, so a skill and a job type cannot drift apart.
  * zones: a manual zone tag on locations FIRST, geocoding second. Do not fake proximity with
    address-string similarity - JOB-DISPATCH.md 2.3 rules that out explicitly.
  * both are HARD filters (a fail removes the worker), never soft score weights.

ALSO RECORDED HERE AND NOT SOLVED: the AZG hour filters in 2.2 (>=11h rest between shifts,
<=12h/day, <=60h/week) are computable from shifts today and are NOT implemented. WARNING from
2.2, repeated because it must not be lost: offering a job 6 hours after clock-out is not a bad
suggestion, it is an employer instructing an illegal shift. The hour rules and the
Kollektivvertrag Denkmal-, Fassaden- und Gebaeudereinigung supplements must be checked by
someone qualified before any automated offer goes out. Do not ship a statutory filter written
from an agent's reading of the statute.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GATE CHECK recorded in the task before any code: >= 15 active workers, and TASK-69 live
- [ ] #2 worker_skills exists and draws job_type from the same closed vocabulary as jobs
- [ ] #3 a zone tag exists on locations and is set by a human; no address-string proximity heuristic anywhere
- [ ] #4 skill and zone act as hard filters, proven by a test where an unskilled worker is absent from the eligible set and the test goes RED if the filter is removed
- [ ] #5 the AZG rest/daily/weekly filters are either implemented against a named legal review, or explicitly deferred in writing - not silently omitted
<!-- AC:END -->
