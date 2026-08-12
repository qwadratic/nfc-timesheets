---
id: TASK-97
title: >-
  gbrain: corpus in the repo, director notes in Postgres, and the drift checks
  that keep both honest
status: To Do
assignee: []
created_date: '2026-08-12 06:03'
labels:
  - assistant
  - docs
dependencies:
  - TASK-93
references:
  - backlog/decisions/decision-36.md
  - ops/check-branding.mjs
documentation:
  - backlog/docs/ADMIN-ASSISTANT.md
priority: medium
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE ONE RULE: gbrain may state facts about the SYSTEM. It may never state facts about the DATA.
'Eine auto_closed-Schicht ist ungeklaert, bis der Mitarbeiter sie bestaetigt hat' belongs in gbrain.
'Wir haben vier Mitarbeiter' belongs in the database, where it is true by construction. A knowledge
base containing a figure is a second source of truth BY CONSTRUCTION.

Two stores, two lifecycles, two approvers (design doc §6.2):
- corpus: server/assistant/gbrain/*.md, in the repo, deployed with the code. Schema in prose, the
  capability catalogue, the German label glossary, the URL param contract (IA doc §5), the accepted
  decisions in one paragraph each, the empty-state rules. Approver: a developer, via a PR.
- notes: gbrain_notes table, APPEND-ONLY with supersedes_id, never updated in place, so 'why did it
  tell me that in March' is answerable. Approver: the director, tier B.

Freshness by digest pinning — the shape of ops/check-branding.mjs (decision-24). Frontmatter:
  describes: server/lib/assistant/registry.js
  describes_sha256: <hash>
node server/assistant/check-gbrain.mjs recomputes and FAILS THE BUILD when the source moved and the
document did not. Stale docs stop being a matter of diligence and become a red check.

Retrieval without a vector database: send the ~2 KB index (id + one-line summary) every turn; the
model fetches a document by id via the tier-A gbrain_read capability. NO embeddings, no chunking.
Ceiling: ~100 documents / ~50 KB of index. Upgrade path: Postgres tsvector (zero deps). pgvector
would be a decision record, not a shrug.

A note unconfirmed for 180 days is shown with '(ungeprueft seit ...)' and surfaced for confirmation.
Never silently deleted — a stale note is still evidence of intent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V13: check-gbrain.mjs refuses a corpus file containing a bare 2+ digit number or a currency amount outside a code fence. RED when 'wir haben 4 Mitarbeiter' is added
- [ ] #2 V14: editing registry.js without updating describes_sha256 fails the build. RED output pasted into notes
- [ ] #3 gbrain_notes is append-only with supersedes_id; a test proves an UPDATE is impossible
- [ ] #4 Index is under 4 KB with the initial corpus; gbrain_read is tier A and returns one document
- [ ] #5 Both checks wired into pnpm check / the same gate as ops/check-branding.mjs
<!-- AC:END -->
