---
id: TASK-135
title: >-
  Proximata product kit: landing template, design system and workflow templates
  reusable across products
status: To Do
assignee: []
created_date: '2026-08-12 16:29'
labels:
  - proximata
  - design
  - meta
  - landing
dependencies: []
priority: medium
ordinal: 135000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner's ask, broader than this repo: standardise the landing pages for ALL products built under Proximata, so that a new product can pull a proven template off the shelf - landing structure, design system, initial setup, and the workflow templates that have actually produced good results first time.

THIS REPO IS THE FIRST INSTANCE, NOT THE OWNER OF THE STANDARD. Build the NFC TimeSheets
landing first (task above), then EXTRACT what generalises. Extracting a standard from one
real example is honest; designing a standard for imagined future products is how you get an
abstraction nobody fits. Wait for the second product before freezing anything.

CANDIDATES TO EXTRACT, once proven here:
  - landing page structure and section order
  - the design token layer (Proximata as house style, per-product brand on top - the Schimmer
    und Glanz mark shows the product brand and the house brand are genuinely different layers)
  - repo setup: gitignore, secret scanning hooks, psst, AGENTS.md skeleton, backlog init
  - the workflow scripts that worked, and equally the ones that did not - a template library
    that only records successes will repeat the failures. The expensive lessons from this
    project are specific and worth carrying: sequence phases around shared files rather than
    maximising parallelism; never git add -A while a workflow writes; a check whose negative
    case cannot fail is not a check; verify layout by LOOKING at a screenshot.

WHERE IT LIVES: not in this repo. This is cross-project, so it needs its own home - ask the
owner where, rather than quietly creating one. Note that ~/.pi/agent/AGENTS.md already holds
the cross-project conventions (demo library, answer format, Telegram channels, and now the
no-local-implementation rule) and is the natural anchor.

OPEN QUESTION for the owner: is Proximata the maker of many products for many customers, or a
single brand customers see? The answer changes whether the house style is visible or invisible
on a product landing page, and it should not be guessed.
<!-- SECTION:DESCRIPTION:END -->
