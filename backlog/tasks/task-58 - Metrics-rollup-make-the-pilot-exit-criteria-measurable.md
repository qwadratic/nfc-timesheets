---
id: TASK-58
title: 'Metrics rollup: make the pilot exit criteria measurable'
status: To Do
assignee: []
created_date: '2026-08-12 05:03'
labels: []
milestone: m-5
dependencies: []
priority: high
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The m-5 exit criterion 10 consecutive working days with no lost shift is not checkable today. There is zero product instrumentation: grep for posthog/plausible/amplitude/mixpanel/umami across server/, web/app, web/lib, ops/ returns nothing. web/app/analytics/page.tsx is CUSTOMER-facing building profitability, not instrumentation.

The only usage signal is the per-request journald access log, unaggregated, rotating away on defaults (no journald.conf, no SystemMaxUse=).

So there is no answer to any pilot question: how many workers activated, shifts logged per day, taps that failed before succeeding, how often the 8h auto-close fires (the proxy for workers forgetting to clock out - the product's core UX failure), or how many shifts get manually corrected.

No vendor needed and decision-16/decision-23's dependency budget argues against one. A nightly SQL rollup into daily_metrics, run by the existing nfc-autoclose.timer pattern, gets activation, shifts/day, auto-close rate and correction rate from data ALREADY in Postgres.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 daily_metrics table plus a nightly rollup job following the ops/systemd/nfc-autoclose.timer pattern
- [ ] #2 Metrics: workers activated, shifts/day, auto-close rate, manual-correction rate, distinct locations tapped
- [ ] #3 A failed-tap counter: client-side count posted with the next successful sync (the tap that fell back to Safari is currently only a Sentry warn at server/routes/wellknown.js:80 that goes nowhere)
- [ ] #4 /health reports last_autoclose_run so a stalled timer is visible from OUTSIDE the box - a silently non-firing 8h timer means every open shift runs all weekend
- [ ] #5 A dashboard tile the director can read without SQL
- [ ] #6 DEMO: show the 10-consecutive-working-days exit criterion being answered from the dashboard, not from a manual query
<!-- AC:END -->
