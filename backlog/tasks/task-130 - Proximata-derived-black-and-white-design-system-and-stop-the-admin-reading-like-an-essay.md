---
id: TASK-130
title: >-
  Proximata-derived black-and-white design system, and stop the admin reading
  like an essay
status: To Do
assignee: []
created_date: '2026-08-12 11:20'
labels:
  - ux
  - design
  - web
  - android
dependencies: []
priority: high
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE COMPLAINT, in the owner's words: something still feels HEAVY. Too much text. Two big white containers that make a screen read like a page to be READ rather than SKIMMED. And the look must not read as default or as demo work - the company positions itself as an innovator, so a stock admin aesthetic actively undercuts the product.

TWO SEPARATE PROBLEMS. Do not let the visual one hide the structural one.

1. LAYOUT WEIGHT - the real issue, and no palette fixes it.
   The verified symptom (12 Aug contact sheet, docs/media/admin-ux-walkthrough.mp4): money
   screens carry FOUR caveat paragraphs; screens open with a subhead, a description, an
   explanation block and a filter card before the first row of data. Every one of those
   sentences was added for a good reason - they are honest and they are load-bearing - and the
   sum is a wall.
   Fix by RANK, not by deletion: the answer first, at a glance; the reasoning one interaction
   away. Existing tasks already start this (108 folds create-forms away, 114 gives each screen
   one question, 115 groups the nav) - READ THEM FIRST and extend rather than duplicate.
   Hard rule: NOTHING TRUE MAY BE DELETED to make a screen lighter. The payroll caveats exist
   because the number is genuinely qualified. Move them, disclose them, typeset them smaller -
   never remove them. A cleaner screen that hides a caveat about money is a downgrade dressed
   as an upgrade.
   Second rule: two stacked white cards is a symptom. Question the CONTAINER, not the text
   inside it - most of these screens probably want one surface, not two, with hierarchy done
   by type and space instead of by boxes.

2. THE VISUAL SYSTEM - black and white, Proximata-derived.
   ASK THE OWNER FOR THE PROXIMATA URL FIRST. It is not recorded anywhere in this repo or in
   ~/Desktop/demos/proximata (checked), and guessing a domain then copying whatever loads is
   how you end up shipping a stranger's brand. Once given: pull the real tokens - type family
   and scale, weights, letter-spacing, spacing rhythm, radii, border treatment, the exact
   blacks and whites and the greys between them, and how it handles emphasis WITHOUT colour.
   Then decide honestly what transfers. A marketing site optimises for a first impression at
   large sizes; an admin optimises for a director reading a number correctly at 14px. Where
   they conflict, the admin wins and the deviation gets written down.
   Constraints that do not bend:
     - NO new npm dependency. Hand-written CSS custom properties in web/app/globals.css, and
       task-106 is already the token foundation - extend it, do not start a parallel system.
     - monochrome does NOT mean throwing away state colour. Five domain states carry meaning
       (open/running, auto-closed-unresolved, corrected, inactive, excluded-from-payroll) and
       colour is their SECOND signal. In a black-and-white system the first signal must get
       stronger - weight, rule, texture, position - and the words must still say it. See
       task-109.
     - CONTRAST IS NOT NEGOTIABLE. A monochrome palette makes it easy to ship elegant grey on
       grey that a director cannot read on a phone in a stairwell. Verify ratios; do not
       eyeball them.
     - Austrian German compounds are long. A layout that only holds at English widths is wrong.
     - the phone card layout (decision-28/30) and every accessibility guarantee survive.
   Android gets the same treatment so both feel made by the same people: the Compose theme
   (ui/Theme.kt) takes the same tokens. Do not fork the values into two hand-maintained lists
   that will drift - state where the shared source of truth lives.

EVIDENCE TO CLOSE: side-by-side before/after of the three heaviest screens at 390px AND
1280px, plus a one-screen Android before/after. Judge them by asking whether the ANSWER is
findable without reading - if a reviewer still has to read the screen, this task is not done,
however good it looks.
<!-- SECTION:DESCRIPTION:END -->

## The brand source arrived, and it is NOT Proximata

Owner sent the company sign on 2026-08-12. Saved to `docs/brand/schimmer-und-glanz-logo.jpg`.

```
SCHIMMER UND GLANZ
GEBAEUDE · DENKMAL · FASSADE
```

Circular badge. Crossed broom and feather duster over a polish tin, sparkles, a lightning
bolt either side of the wordmark. Type is an upright condensed sans, wide-tracked, set on a
circular path.

**IT IS ALREADY MONOCHROME.** Black plate, white disc, dark slate-grey mark. So the
black-and-white direction is not a stylistic preference to be defended - it is the company's
existing identity, and matching it is the cheap correct answer. That resolves the open
question in this task: build the system from THIS, and treat Proximata as the *house* layer
underneath (the maker's mark), not as the surface.

Two things to establish before designing, because guessing either wastes the pass:
- the sign is a PHOTOGRAPH under office lighting, so its greys are not the brand's greys.
  Ask for a vector or the original artwork before sampling colour from a JPEG.
- the trade line reads GEBAEUDE · DENKMAL · FASSADE - building, monument, facade. Monument
  and facade work is NOT what this app currently models. Do not quietly encode a narrower
  business than the customer runs.

Where this leaves the earlier instruction: the admin still wants to feel Proximata-made, and
the cleaning company's own customers should see Schimmer und Glanz. Those are two audiences
and probably two surfaces - say which is which before writing tokens.
