---
id: TASK-75
title: >-
  Job incidents and materials: reuse the existing lifecycles, do not grow a
  second one
status: To Do
assignee: []
created_date: '2026-08-12 05:47'
labels:
  - design
  - server
  - web
  - ux
milestone: m-6
dependencies:
  - TASK-69
  - TASK-47
  - TASK-64
  - TASK-61
documentation:
  - backlog/docs/JOB-DISPATCH.md
priority: low
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHY. JOB-DISPATCH.md sections 5 and 6. A job that needs materials the worker does not have is a wasted trip, and any human must be able to report an incident against a job. Both already have a home in this system, and the risk is that dispatch grows parallel copies.

MATERIALS (section 5). ponytail: DO NOT build a per-worker stock ledger. At accept time, one
question - 'you will need: mop, pH-neutral cleaner. Do you have these? Ja/Nein'. Self-report.
Cost of being wrong is one wasted trip; cost of a ledger is a second inventory system that is
wrong within a week of nobody updating it. Gate for revisiting: >5 measured wasted trips/month
or >EUR 2000/month materials spend.

  'Nein' -> job.status = blocked_materials (leaves the feed; blocked is NOT unfilled)
         -> INSERT material_requests: worker_id, location_id = job location, body prefilled
            from required_items and EDITABLE by the worker, status 'submitted'
         -> link row job_material_requests(job_id, material_request_id)

  request approved -> job does NOTHING. approved is not arrived.
  request ordered  -> job does NOTHING; the director sees an ETA next to the blocked job.
  request arrived  -> job returns to qualified at its ORIGINAL price step.
  request rejected -> job goes to a HUMAN. Never silently dropped or auto-cancelled.

  TWO PROHIBITIONS, both from 005_v2_features.sql and decision-6:
  * dispatch must NEVER auto-advance a material request, and must never fuzzy-match free text
    to inventory_items. 005 forbids both on purpose.
  * a job must NEVER charge cost_cents to its location_id. That is option B, which decision-6
    explicitly rejected. Attribution stays pro-rata by labour hours. Doing otherwise needs a
    new decision record first.

INCIDENTS (section 6). Worker, admin and client contact can all report; the client contact via
the existing tokened portal. IDENTITY COMES FROM THE SESSION, NEVER THE BODY (decision-22 /
decision-31) - a reporter field a client can set is a reporter field a client can forge.
Severities S1/S2/S3 per TASK-64. internal_note is an admin-only column separate from body and
must be VISIBLY LABELLED internal in the UI. Not logged in v1: photos, background location.

VISIBILITY: director all; worker their own; client contact only what they filed, status only,
never internal_note.

RETENTION is a proposal in 6.4 and needs the legal sign-off tracked in TASK-61. Do not ship
agent-invented retention periods as if they were legal advice. Note the real blocker: dispatch
ADDS personal data (offers, declines, no-show marks, incident bodies) to a system whose
erasure path is still 'UPDATE workers SET active=false'. Do not add the data before the path
exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the accept screen asks the materials yes/no question in German and records the answer
- [ ] #2 'Nein' creates a material_requests row in status submitted, linked to the job, with the worker able to edit the prefilled body
- [ ] #3 job leaves blocked_materials ONLY on the linked request reaching arrived; a test asserts approved and ordered do NOT unblock it, and goes RED if they do
- [ ] #4 a rejected request routes the job to a human queue; no code path auto-cancels it
- [ ] #5 a test asserts no dispatch code advances a material_requests status and none writes cost_cents against a location_id (decision-6), going RED if either is introduced
- [ ] #6 incidents can be filed against a job by worker, admin and client contact, with reporter identity taken from the session
- [ ] #7 internal_note is never present in any worker-facing or portal-facing response, proven by a test on the response shape
- [ ] #8 retention periods are signed off under TASK-61 before this ships, or the personal-data-adding parts are held back
<!-- AC:END -->
