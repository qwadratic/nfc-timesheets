---
id: TASK-134
title: >-
  Landing page that answers the basic questions, shows the demos, and looks made
  on purpose
status: To Do
assignee: []
created_date: '2026-08-12 16:29'
labels:
  - ux
  - web
  - landing
  - marketing
dependencies: []
priority: medium
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A public landing page for the product. Owner's brief: answers the basic questions, carries the demos, states the differentiating features, must look COOL - and must not read as default or as demo work, because the company positions itself as an innovator and a stock template contradicts the pitch.

CONTENT, in the order a stranger needs it:
  - what it is, in one sentence, without jargon
  - the tap: a worker holds a phone to a tag on the wall and the hours are recorded. This is
    the whole product in one gesture and it should be the first thing seen, moving.
  - the demos already exist and are already redacted: docs/media/*.mp4. Reuse them. Do not
    record new marketing footage while real ones sit unused.
  - differentiating features, stated honestly. Say what it does not do.
  - who made it: Proximata below, as the maker's mark.

HOSTING: decision-16 puts everything on one VM in one process, and the admin is already a
static export served from PUBLIC_DIR. The landing page follows the same path - static, no new
dependency, no second host to keep alive. Say explicitly which URL it lives at and what
happens at the root, since / currently serves the admin.

GERMAN FIRST, en in the switcher, exact key parity - the same rule the admin follows. A
marketing page that reads as translated undercuts the same claim the design is making.

MUST NOT: leak customer data. The demos are redacted but the copy is a fresh chance to name a
real building or a real person by accident. No customer names, no addresses, no tag URLs.

PERFORMANCE IS PART OF LOOKING GOOD: a landing page that loads slowly reads as amateur no
matter how it is designed. Budget the video, do not autoplay with sound, and make it work on
a phone on mobile data.

DEPENDS ON the design system task (130) for tokens - do not invent a second visual language
for the landing that the product then contradicts.
<!-- SECTION:DESCRIPTION:END -->
