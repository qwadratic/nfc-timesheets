---
id: decision-7
title: Desktop-first web admin - no mobile layout (blocker message)
date: '2026-07-28 13:51'
status: superseded
superseded_by: decision-29
---

> **SUPERSEDED by decision-29 (2026-08-12).** The mobile blocker is gone; the admin panel
> works on a phone. Do not implement anything below. Kept because decision-29 argues against
> it directly and that argument needs its opposing text to remain readable.
>
> Status was still `accepted` until the 2026-08-12 backlog audit, which means agents reading
> this directory would have treated the blocker as binding for eight days after it was reversed.

## Context

Admin panel has complex views (map, tables, side panels). Building responsive layouts for all breakpoints is significant effort for a pilot.

## Decision

Below 1024px viewport: show full-screen blocker message "NFC TimeSheets Admin is designed for desktop." Above 1024px: full sidebar nav + content layout. No responsive admin for this iteration.

## Consequences

- Faster development — one layout to build and test
- Admin on tablet/phone blocked entirely
- Acceptable: admin tasks are office work, not field work. Workers use the iOS app.
