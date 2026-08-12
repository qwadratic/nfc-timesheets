# UX review — adversarial, by execution

Date: 2026-08-12 · Reviewer: review agent 13 · Scope: everything this run produced
(24 modified files, 6 decisions, 11 docs, 24 tasks, 5 demo scripts, 96 screenshots)

Production touched **read-only**. Every mutation made below was reverted and the revert
verified byte-for-byte (`diff -q` against a pre-mutation copy, four files, all OK).

---

## Verdict

**The gates are green and the money is still wrong.**

```
pnpm verify            ✓ exit 0     server check-api.js   ✓ PASS (scratch db)
check-design-tokens    ✓ 5 + 6 RED  check-close-flag      ✓ 7 pass 0 fail
demo/check-guards.sh   ✓ 24 ok      check-migrate         ✓ OK
demo/check-record.mjs  ✓ 12 ok      android/checks/run.sh ✓ 2 ok
demo/ux-probe.mjs      ✓ 16/16      ops/check-branding    ✓ 8 ok
gitleaks (23 commits)  ✓ no leaks   prod /health          ✓ 200
gitleaks (this run's 116 files) ✓ no leaks
prod: 8 shifts · 4 workers · 1 location · migrations 001–005 ✓ untouched
```

And yet, from the **current** build, `/payroll/` at 390px:

```
server total    1.093,25 €
screen total  121.334,00 €        ← 111× higher
caveat        „Diese Summe ist daher ZU NIEDRIG."
bullet 1      „…aus diesen Gründen fehlt nichts."   ← directly above bullet 2 saying a chunk is missing
CSV button    enabled, carries no caveat
header        „3 Mitarbeiter, 8.000,00 Stunden"     ← 86 h/person/day, stated without comment
```

**Is it prettier but not clearer?** On the money screens: yes, and I will not soften that.
`/payroll/` gained a friendly subtitle, a folded „Wie diese Seite funktioniert", labelled
cards, „Diese Stunden nachrechnen" links and a labelled Gesamt row. The one number an
accountant pays from is off by 111× and captioned with the wrong sign. Four new caveat
paragraphs surround a figure that no caveat describes correctly. That is polish arranged
around an untreated wound.

Everywhere else the work is genuinely good and I could not break it: the error states are
real error cards with retry (`shifts-error-500` regenerated from HEAD — see §4), the phone
layout holds at 390px on every screen, the token floor is mutation-proven, and the demo
guards are the best-engineered checks in this repo.

**Blocking:** F1 (money check absent), F2 (label probe cannot fail), F3 (stale evidence).
Non-blocking but must be fixed before the next agent reads AGENTS.md: F4, F5.

---

## 1 · Decisions

Read all 36. Six new, all `status: proposed`, all with an explicit relationship section.
decision-31 names its partial supersession of 22 and 26 in prose. 32–35 say "Supersedes
nothing." That part is done properly.

**F4 · decision-31 is missing from the AGENTS.md checklist.** Measured:

```
grep -c decision-31 AGENTS.md  ->  0
grep -c decision-32 AGENTS.md  ->  1     33 -> 1   34 -> 1   35 -> 1   36 -> 1
```

The single most consequential of the six — worker identity moves from Sign in with Apple to
SMS OTP — is the one that did not make the list. In the same file that says, forty lines
below the gap:

> **This checklist is load-bearing and it went stale for eight days.**

The run reopened the hole while writing the sentence about it. `low` effort to fix.

**F5 · `decision-28` is cited as binding in four new tasks and in operator-facing German.**
decision-28 is struck through in AGENTS.md — **superseded by decision-30**.

```
task-105  "MUST NOT REGRESS: … decision-28 (labour valued at current rates until worker_rates exists)"
task-117  "MUST NOT REGRESS: … decision-28 contract …"
task-116, task-110                also cite it
web/messages/{de,en}.json:710     "…(decision-28)."   ← shipped to the director, in German
web/app/layout.tsx:29             "decision-28: the panel works on a phone"   ← that is decision-29
web/app/reinigung/page.tsx:24     "removed in decision-28"                    ← decision-29
web/app/globals.css:1273 + 1354   same drift
```

TASK-110 exists *because* six strings print internal ADR ids — and its own body then cites
the superseded one. Two money tasks (105, 117) pin a retired record as a
must-not-regress constraint, so an implementer following them will preserve behaviour
decision-30 already replaced. Also: decision-22 and decision-26 carry **no forward pointer**
to decision-31, so a reader landing on decision-22 cannot tell a replacement is on the table.

Nothing in the *code* contradicts an accepted decision. Dependency budget held (`pg` +
`@sentry/node`; web adds zero npm deps). Money is integer cents throughout `lib/payroll.ts`
and `lib/pl.ts`. de/en parity **881/881 exact** (task-104 says "814/814 today" — already stale).

---

## 2 · The checks, mutation-tested

Five mutations. Each applied, measured, reverted, revert verified.

| # | mutation | expected | got |
|---|---|---|---|
| M1 | delete `payroll.caveatReconcile` from de.json | RED | ✓ RED, exit 1, names the key |
| M2 | invert the sign in `reconcile()` | RED | ✗ **GREEN** |
| M3 | shift every `data-label` one column | RED | ✗ **GREEN** |
| M4 | `ux-probe --mutate audit-baseline` (CSS) | RED | ✓ 3 probes RED |
| M5 | `--ink-muted` → `#9aa4b2` (fails 4.5:1) | RED | ✓ RED, exit 1 |

### F1 · `lib/payroll.ts` has zero check coverage — proven

```
web/lib/payroll.ts:180
-  missingCents: serverCents - visibleCents
+  missingCents: visibleCents - serverCents

pnpm check   -> exit 0, "All checks passed."
tsc --noEmit -> exit 0, "No errors found"
```

`scripts/check.mjs` is 700 lines and covers `period.ts`, `pl.ts`, `materials.ts`, `map.ts`,
`enrolment.ts`, `params.ts`. It does not import `payroll.ts` once —
`grep -n "reconcile\|payrollFor\|coverageOf" scripts/check.mjs` returns only comment
matches. The one module that decides what a person is paid is the one module nobody checks.
That is why TASK-104's bug survived: not an oversight in review, an absence of a gate.

∴ every claim of the form "pnpm verify is green" carries **no information about payroll
arithmetic**.

### F2 · the phone-label probe cannot fail the way it says it can

`demo/ux-probe.mjs:249` — *"RED if the `tfoot` loop is removed from
`components/ResponsiveTableLabels.tsx`."* Two problems.

1. `MUTATIONS` has exactly **one** entry and it rewrites **CSS strings only**. No mutation
   touches TSX. 13 of 16 probes have no falsification evidence at all; `--mutate
   audit-baseline` reddens 3.
2. The assertion is `foot.labelled === foot.withValue` — a **count**. The file's own header
   says why that is the wrong shape:

   > `data-label` counts were 791/791 correct while the labels were off by one column

I shifted the labels one column (`headings[i]` → `headings[i + 1]`), rebuilt, re-ran:

```
baseline   ok  …  ["Stunden",       null, "Betrag",        null]
mutated    ok  …  ["Stundensatz",   null, "Nicht gezählt", null]

All 16 layout probes passed.       exit 0
```

Under the mutation the phone totals card captions the **hours total „Stundensatz"** and the
**euro total „Nicht gezählt"** — and the probe printed those exact strings in its own output
and called itself `ok`. Readable and false, which the component comment correctly calls
worse than unlabelled. The check compares a number to a number; it never compares the label
text to the heading it claims to copy.

Fix: assert `labels[i] === headings[i]` for every labelled cell, and add a TSX mutation to
`MUTATIONS` so the rebuild path is exercised. `low` effort.

### What is solid

- `demo/check-guards.sh` — 24 ok. The design is right for the reason stated in its own
  header: it matches the **refusal message**, not the exit code, because a guard-less run
  still exits non-zero by being 401'd at production. `must_refuse` treats *surviving 5 s* as
  a failure, so a deleted guard cannot hang its way to green. Best checks in the repo.
- `check-design-tokens.mjs` — self-testing, 6 RED proofs, and it verifies the mutant
  applied. M5 confirmed independently: it recomputes contrast, it does not assert a
  remembered ratio.
- `ux-probe.mjs` exit logic — `mutationApplied` is checked and exits 2 if the mutation never
  landed. Correct. The gap is coverage, not plumbing.
- `check-api.js` — full PASS against scratch `nfc_review_scratch`, including forged-Apple-key
  cases and cross-worker material-request isolation.

---

## 3 · Secrets

```
gitleaks detect (23 commits)                      -> no leaks found
gitleaks detect --no-git over this run's 116 files -> no leaks found
psst scan                                          -> 2 name-shaped hits (PORT, APP_KEY), no values,
                                                      none in a file this run produced
```

`--no-git` over the whole tree reports 47, **all in ignored paths** — `.gstack/` (30),
`.firecrawl/` (9), `web/.next/` build cache (6), `android/keystore.properties` (2). Each
confirmed ignored via `git check-ignore -v`; `keystore.properties` is untracked. Pre-existing,
not this run, nothing committable.

Images checked: the 4 phone PNGs and the payroll/shifts/dashboard states carry fixture names
(`Bálint Kovács`, `Anna Nowak`, `HOIV Arsenalstraße 11`, `*@example.at`). No real credential,
no real customer PII rendered. ✓

⚠ `demo/ux-states.mjs` hardcodes `/Users/gerhardgustav/Desktop/ai-automations/...` in three
places (lines 7, 9). Not a secret, but it is an absolute home path heading for a public repo
and the script will not run for anyone else.

---

## 4 · Accessibility and the phone, by picture

Read the images, not the assertions.

- 390px, all 11 screens: `sideways=false`. Page never scrolls horizontally; the nav strip
  does, deliberately (`.nav-list { flex-wrap: nowrap }` inside `.sidebar { overflow-x: auto }`).
- Touch targets ≥44px: **one** violation across 48 states × 2 widths —
  `clients-empty` at 390px, `sub44=1`. Everything else 0.
- Contrast: mutation-proven recomputed, not asserted (M5).
- `prefers-reduced-motion` turns motion off globally — check present and RED-proven.
- Totals row is labelled on a phone (`Gesamt · STUNDEN 8.000,00 · BETRAG 121.334,00 €`) ✓
  — the labels are right today; F2 is that nothing would tell us if they stopped being.

⚠ `pnpm lint` emits **4 `noDescendingSpecificity` warnings**, all in the new phone block
(`globals.css:1402–1406`): the 44px touch-target rule for `input, select, textarea` has
lower specificity than `.field textarea` above it. Biome is warning that the touch-target
floor **may not apply to `.field` inputs**. It does not fail the build. It is the
accessibility rule the whole phone block exists for, and it is the only lint warning in 48
files. Verify by measurement, then reorder or raise specificity.

### F3 · the committed evidence depicts code that no longer exists

```
docs/media/states/*.png          mtime 06:53   (96 files)
web/components/DataState.tsx     mtime 08:22
web/app/page.tsx                 mtime 08:25
web/app/shifts/page.tsx          mtime 09:30
```

Every screenshot predates the fixes by 1.5–2.5 h. `UX-AUDIT.md` is honest about this
("**No code was changed.**") — but a different agent then changed 2 876 lines, and nobody
re-captured. Consequences, measured:

- `shifts-error-500-390.png` (committed) shows the error line **and** „Schichten werden
  geladen…" together, forever. I regenerated it from HEAD: the current build renders a
  proper error card — headline, body, **„Erneut versuchen"** button, no loading text. The
  committed picture shows a bug that is fixed.
- Re-running `demo/ux-states.mjs` now emits **112** files, not 96. Sixteen states captured
  by the current harness — `shifts-link-unknown-worker`, `shifts-link-malformed`,
  `payroll-english`, `shifts-create-open`, … — have **no committed screenshot at all**.
  Those are the G2–G5 URL-contract states, i.e. the ones `check.mjs` just gained coverage for.
- There is no README and no commit marker in `docs/media/states/`, so nothing tells a reader
  which tree they are looking at.

An evidence directory that silently disagrees with HEAD is worse than an empty one. Either
regenerate on every verify, or stamp the commit into the directory.

---

## 5 · Board truth

All of TASK-104…127 are `To Do`. Correct for 104 and 105 (verified un-fixed, below).
Questionable for the rest: DataState/`lib/load.ts` (TASK-107) is imported by **11 of 13
pages**, the `.disclosure` fold (TASK-108) is visible in every regenerated screenshot, and
`globals.css` grew 723 lines of the TASK-106 token floor. The plan's wave order is
**W1 money → W2 floor → W3 failure visible**; the tree contains W2, W3 and part of W4, and
**none of W1**. The riskiest work was correctly identified, correctly ranked first, and is
the only work not started.

Simulation report says `check-guards.sh` is "now 22 ok". It is **24 ok**. Stale by two.

---

## The three things most likely to be wrong

### 1 · The payroll total is wrong in a direction nobody will notice, and the CSV carries it out of the building

Not "likely" — **verified from the current build**. `reconcile()` returns
`serverCents - visibleCents` and no caller reads `Math.sign`, so an over-count is announced
as an under-count. Server 1.093,25 € vs screen 121.334,00 €, captioned „zu niedrig". The
first caveat bullet says „fehlt nichts" immediately above the bullet saying otherwise.
`CSV herunterladen` is enabled and `downloadCsv` writes no caveat row. And M2 proves no gate
would catch the sign flipping again tomorrow.

**Evidence that settles it:** a runnable check in `scripts/check.mjs` over `lib/payroll.ts`
with three fixtures — `visible < server`, `visible > server`, `visible === server` —
asserting the chosen message key for each; shown RED against today's file, with the RED
output pasted into TASK-104's notes, then GREEN. Same file must assert `toCsv` output
contains the caveat row whenever a caveat is live. Until that check exists and has been seen
red, no statement about payroll correctness in this repo is evidence.

### 2 · The phone card labels are one column off somewhere, and nothing can tell us

M3 proves the only probe guarding them compares counts, not text, and passes while captioning
euros „Nicht gezählt". This exact bug has shipped in this project once already. It is now
guarded by a check with the same blind spot as the assertion that missed it the first time.
Eleven screens × dozens of rows are covered by that single count.

**Evidence that settles it:** change the probe to assert `labels[i] === headings[i]` per
labelled cell across **all** `.data-table` tables at 390px, not just `/payroll/` `tfoot`;
add a TSX mutation (`headings[i]` → `headings[i+1]`) to `MUTATIONS`; show it RED. If it goes
red on any screen *before* the fix, that screen is already mislabelled in production.

### 3 · `docs/media/states/` is the record of a tree that does not exist, and the audit reasons from it

96 PNGs from 06:53 against source last touched 09:30; the harness now produces 112. Three of
the "ten worst" findings in UX-AUDIT are cited by screenshot filename. At least one
(finding 1, error + loading) is already fixed; nothing marks it so. The inverse risk is the
dangerous one: a finding that looks fixed in a stale picture but is not, and gets closed.

**Evidence that settles it:** regenerate all states from HEAD, `cmp` each against the
committed file, and list the differences. Any file that differs was reasoned about wrongly.
Then make regeneration part of the gate — a screenshot with no commit stamp is a claim with
no date.

---

## Also fix (low effort, high leverage)

```
F4  add decision-31 to the AGENTS.md checklist                          1 line
F5  correct decision-28 → 29/30 in 4 tasks, 2 message keys, 4 comments   ~10 lines
    add a forward pointer in decision-22 and decision-26 to decision-31
—   4 noDescendingSpecificity warnings on the 44px touch-target rule
—   demo/ux-states.mjs: 3 hardcoded /Users/gerhardgustav paths
—   SIMULATION-REPORT.md says 22 guards; there are 24
—   task-104 says de/en parity is 814/814; it is 881/881
```

---

## Commands run

```
web:     pnpm verify · pnpm check · pnpm lint · pnpm build            all exit 0
server:  DATABASE_URL=postgres:///nfc_review_scratch node db/migrate.js
         node check-api.js                                            PASS
         node server/check-close-flag.mjs                              7/0
         node server/db/check-migrate.js                               OK
demo:    sh demo/check-guards.sh                                       24 ok
         node demo/check-record.mjs                                    12 ok
         node demo/ux-probe.mjs                                        16/16
         node demo/ux-probe.mjs --mutate audit-baseline                3 RED ✓
         SHOT_DIR=/tmp/states-now node demo/ux-states.mjs              112 files
ops:     node ops/check-branding.mjs                                   8 ok
android: sh android/checks/run.sh                                      2 ok
secrets: gitleaks detect · gitleaks detect --no-git · psst scan
prod:    curl /health -> 200 · ssh + SELECT (read-only): 8/4/1, migrations 001–005
cleanup: dropdb nfc_review_scratch · 4 mutated files restored and diff-verified
```
