---
id: TASK-67
title: >-
  Pre-commit hook: PSST_SKIP_SCAN=1 silently disables gitleaks too, and
  PORT=8000 false-positives every backlog ordinal
status: To Do
assignee: []
created_date: '2026-08-12 05:14'
labels: []
milestone: m-5
dependencies: []
priority: medium
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two defects in .githooks/pre-commit, both hit for real on 2026-08-12.

DEFECT 1 - the bypass is mis-scoped and mis-named. Line 6 is:
  [ "$PSST_SKIP_SCAN" = "1" ] && exit 0
That exits the WHOLE hook, so a flag named PSST_SKIP_SCAN also disables gitleaks - the entropy/regex layer that catches third-party API keys NOT in the vault. The two layers are documented on lines 2-4 as deliberately complementary, and the bypass silently collapses both. Anyone bypassing a psst false positive loses entropy scanning without being told.

DEFECT 2 - PORT=8000 in the vault false-positives on every backlog ordinal. psst does exact vault-VALUE substring matching. The backlog CLI generates ordinal: <task-id> x 1000, so tasks 8, 18, 28, 38, 48, 58 all produce an ordinal ENDING in 8000 and every one trips the scanner. Observed on task-18, task-38, task-48 and task-58 in a single commit. ordinal: 18000 is byte-identical in 75834a2, so this has been firing since before this branch and will fire on roughly one task in ten forever.

The real cost is not the block, it is the habit: a scanner that cries wolf on a routine metadata field trains everyone to reach for the bypass, and the bypass turns off the layer that actually catches API keys.

DO NOT fix this by disabling scanning. Per the repo's own .gitleaks.toml commentary, allowlist by sentinel, never by path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PSST_SKIP_SCAN=1 skips ONLY the psst layer; gitleaks still runs. Add a separate GITLEAKS_SKIP_SCAN=1 if a gitleaks bypass is ever needed, and make the failure message name which layer was skipped
- [ ] #2 The PORT/ordinal false positive is resolved without weakening the scan - either scope psst to exclude backlog/**/*.md frontmatter, or give the vault entry a value that is not a 4-digit substring of routine numbers
- [ ] #3 A check asserts the hook fails closed: stage a file containing a real high-entropy token and confirm the commit is refused even with PSST_SKIP_SCAN=1 set
- [ ] #4 DEMO: stage a fake AWS key with PSST_SKIP_SCAN=1 set and show the commit still refused
<!-- AC:END -->
