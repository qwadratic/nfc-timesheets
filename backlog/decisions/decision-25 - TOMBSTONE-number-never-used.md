---
id: decision-25
title: TOMBSTONE — this number was never used
status: tombstone
date: '2026-08-12'
supersedes: nothing
---

## Why this file exists

There is no decision-25. The sequence runs 24, [gap], 26, and a gap with no explanation is a
thing every future reader stops and re-investigates. This file is here so that costs thirty
seconds once instead of twenty minutes repeatedly.

## What happened

`decision-27` (Play Console, 2026-08-03) cites "the portal's GDPR reasoning in decision-25" —
so a record with this number was intended, and the reasoning it refers to was real. No file was
ever committed. `git log --diff-filter=A -- 'backlog/decisions/decision-25*'` returns nothing:
it was never added and then deleted, it simply never landed.

The GDPR reasoning that decision-25 was meant to carry is not lost — the data-minimisation
argument it described is visible in the code at `server/routes/portal.js:25-30`, which limits
the client portal payload to `{building, date, first name, minutes}` and says why in a comment.

## What to do about it

Nothing. Do not reuse the number — a citation in decision-27 already points at it, and
rebinding it to different content would make that citation silently wrong.

The GDPR work itself is **not** covered by this tombstone. It is tracked as real tasks under
milestone m-6 (privacy policy, erasure path, retention policy, DPA). See the task board.
