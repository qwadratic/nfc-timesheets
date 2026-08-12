---
id: TASK-133
title: 'Docs tab in the admin portal, backed by procedures written once and reused'
status: To Do
assignee: []
created_date: '2026-08-12 16:28'
labels:
  - ux
  - web
  - docs
dependencies: []
priority: medium
ordinal: 133000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner wants a DOCS tab inside the admin portal, and the operating procedures standardised from scratch rather than living in an agent's head or in fifteen session reports.

TWO HALVES, and the second is the valuable one:

1. THE TAB. A docs section in the admin, in German, reachable from the nav. Static export
   means it ships as pages, not a CMS - which is correct here, since the docs version with the
   code that they describe. No new dependency.

2. THE PROCEDURES THEMSELVES. Right now the answer to 'what do I do when X' lives in
   backlog/docs across roughly fifteen session reports of wildly different lifetimes - task-65
   already exists to split durable docs from archived reports, so START THERE rather than
   inventing a parallel structure.
   The simulation task (demo/simulate.mjs, SIMULATION-REPORT.md) was specifically asked to
   enumerate what the app tells a director when something unexpected happens, and where the
   answer was 'nothing'. THAT LIST IS THE TABLE OF CONTENTS for this tab. Do not write generic
   help pages; write the answers to the situations that actually occurred.

ORDER OF ANSWERS, from the owner's earlier instruction: in-app guidance first, then a help
page or manual, then an onboarding or a feature video, then an FAQ. A PERSON'S PHONE NUMBER
IS THE LAST RESORT, never the first answer.

Known real incidents that MUST have a documented procedure, because each already happened:
  - a worker cannot clock out (adopted tag, no URL - the manual scan path)
  - an enrolment code expired before it was used
  - a shift is stuck open and must be force-closed, with a note saying why
  - a tap did nothing (the tag is not ours / NFC off / Android needs the screen unlocked)
  - a worker has no hourly rate and silently prices at zero
  - month-end: what payroll excludes, and why the figure is qualified

CROSS-LINK: every doc page is reachable from the screen it is about, and every screen with a
non-obvious rule links to its page. Docs nobody can find are docs nobody reads.
<!-- SECTION:DESCRIPTION:END -->
