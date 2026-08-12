# Design system — NFC TimeSheets admin

Date: 2026-08-12 · Status: **proposal, nothing applied** · Scope: `web/app/globals.css` + the
eleven admin screens · Input: `backlog/docs/UX-AUDIT.md`

One stylesheet, hand-written, CSS custom properties. **No npm dependency, no Tailwind, no
component library, no CSS-in-JS.** Survives `output: 'export'` because it is one static file.
Survives decision-28 because every rule below is written card-first for `<768px` and
table-first above, in that order.

Default language is Austrian business German. Every sizing rule is content-sized
(`ch`/`rem`/`min-content`), never a magic pixel width. A design that only fits
„Payroll" and not „Lohnabrechnungszeitraum" is wrong.

**Class names do not change.** This system is a set of values and contracts fitted to the
markup that exists. New class names appear only where the audit found a missing component
(`.data-state`, `.button-row`, `.button-danger`, `.disclosure`, `.num`, `.panel`).

---

## 0 · The five rules that outrank taste

1. **Colour is never the only signal.** Word first, texture second, tint third. Verify in
   greyscale; a print of the payroll screen must lose nothing.
2. **A number never reflows.** Money and hours are tabular, right-aligned, non-breaking,
   and their column has a reserved min-width. `1.20 / 0,00 / €` on three lines is a defect
   (finding 3).
3. **Never both.** Loading, empty, error and content are four mutually exclusive states of
   one region. Error + „Wird geladen…" forever is the worst bug in the panel (finding 1).
4. **Content sizes the box.** No `nowrap` on a translated string, no fixed-width button, no
   `overflow-wrap: anywhere` on prose (finding 3).
5. **Accessibility is a contract, not a polish pass.** Focus ring, 44px coarse target, live
   region, name-role-value. None of these is tradeable for a nicer screenshot.

---

## 1 · Type scale

Base `1rem = 16px`, pinned on `body` today. **Keep the pin on `body`; keep `rem` everywhere
else** — the portal (`/reinigung/`) deliberately escapes it and that stays.

Four sizes for the app, plus two heading sizes. Current file has `0.72 / 0.8 / 0.85 / 0.9 /
0.95 / 1.05 / 1.25 / 1.75rem` — eight sizes, no scale. Collapse to six.

| token | value | px | used for | line-height |
|---|---|---|---|---|
| `--text-xs` | `0.75rem` | 12 | `data-label` caps, `nav-heading`, `tag-uuid` | `--leading-tight` |
| `--text-sm` | `0.875rem` | 14 | hints, errors, table `thead`, badges, code, footer | `--leading-dense` |
| `--text-base` | `1rem` | 16 | body, table cells, inputs, buttons, nav | `--leading-body` |
| `--text-md` | `1.125rem` | 18 | `page-summary`, phone card title | `--leading-dense` |
| `--text-lg` | `1.375rem` | 22 | `h2` | `--leading-tight` |
| `--text-xl` | `1.75rem` | 28 | `h1` | `--leading-tight` |

```
--leading-tight: 1.25   headings, badges, single-line labels
--leading-dense: 1.4    table cells, hints — two German lines still readable
--leading-body:  1.55   prose
```

Rules:
- **12px floor.** Nothing smaller, ever. Today's `0.72rem` (11.5px) and `0.8rem` (12.8px)
  both collapse into `--text-xs`; `0.85rem`/`0.9rem`/`0.95rem` collapse into `--text-sm`.
- Weights: `400` body · `600` labels, badges, card titles, `th` · `700` totals row and
  `nav-heading` only. No `500`, no `800`.
- `font-family` unchanged (`system-ui` stack). Monospace stack unchanged, and monospace is
  reserved for identifiers that get read aloud on a support call (slug, UUID, tag URI).
- Measure: prose `max-width: 70ch`, hints `60ch`, callout lists `80ch`. German runs ~30%
  longer than English; `ch` follows the font, a pixel width does not.
- `hyphens: auto` on prose and table cells. `<html lang>` is already rewritten per locale by
  `IntlProvider`, so German hyphenation dictionaries actually apply — this is the correct
  answer to long compounds, and `overflow-wrap: anywhere` is not (finding 3).

## 2 · Spacing scale

4px base, geometric-ish, six steps. Same tokens as today plus one, minus none.

```
--space-1: 0.25rem   4px   icon gap, hint gap, badge padding-y
--space-2: 0.5rem    8px   label→control, inline button gap
--space-3: 0.75rem  12px   cell padding-x, control padding-x
--space-4: 1rem     16px   field→field, paragraph
--space-6: 1.5rem   24px   panel padding, section gap
--space-8: 2rem     32px   page padding, block→block
```

Density pair (§9) is the only place a spacing value is conditional:

```
--row-y: var(--space-2)   phone card rows and comfortable tables
--row-y: 0.375rem         ≥768px data tables (6px) — set inside the media query
```

Nothing gets a bespoke margin. If a gap is not on the scale it is a bug.

## 3 · Colour roles

Semantic names only. **No token is named after a hue** — `--state-caution`, never
`--amber`. Every ratio below is measured, not asserted (§11 pins them in a check; the audit
explicitly never measured contrast).

### Surfaces and ink

| token | value | role | contrast |
|---|---|---|---|
| `--bg-app` | `#f6f7f9` | page background | — |
| `--bg-surface` | `#ffffff` | cards, tables, panels, inputs | — |
| `--bg-sunken` | `#f6f7f9` | code chips, inert badges, disabled fields | — |
| `--ink` | `#16191d` | body text | 17.6 on surface · 16.5 on app |
| `--ink-muted` | `#5b6472` | hints, `thead`, secondary sentences | **5.98** · 5.58 |
| `--ink-inverse` | `#ffffff` | text on `--accent`, tooltip text | 6.84 on accent |
| `--border-subtle` | `#d8dce3` | decorative rules: table rows, card outline | 1.38 — decorative **only** |
| `--border-strong` | `#868d97` | **every interactive boundary**: input, select, textarea, secondary button | **3.35** · 3.12 ✓ 1.4.11 |
| `--border-focus` | `#0b63d6` | focus ring | 5.57 · 5.20 |

⚠ `--border-strong` is new and is a real accessibility fix: today an input's only boundary is
`#d8dce3` at **1.38:1**, which fails WCAG 1.4.11 (3:1 for the visual boundary of a control).
The subtle border stays for table rules and card edges, where the boundary is decorative and
the content is what delimits.

### Action

| token | value | role | contrast |
|---|---|---|---|
| `--accent` | `#1f5aa6` | primary button fill, links, current nav | 6.84 on surface |
| `--accent-hover` | `#17457f` | primary hover/active fill | 9.57 vs white text |
| `--accent-soft` | `#e8f0fa` | nav current, notice background, badge tint | — |
| `--accent-ink` | `#14406f` | text on `--accent-soft` | **9.17** |

### Feedback

| token | value | role | contrast |
|---|---|---|---|
| `--danger` | `#a4262c` | error text, destructive button fill, invalid border | 7.26 on surface · 7.26 vs white |
| `--danger-soft` | `#fdeaea` | error callout background | — |
| `--caution` | `#8a5a00` | caution border, caution icon-free rule | 5.93 |
| `--caution-soft` | `#fdf0d5` | caution callout / badge tint | — |
| `--caution-ink` | `#6b4400` | text on `--caution-soft` | **7.59** |
| `--ok` | `#1c6b3c` | success status line | 6.53 |
| `--ok-soft` | `#e7f4ec` | success callout background | 5.76 for `--ok` on it |

Every text pair ≥ 4.5:1; most ≥ 7:1 (AAA). Every non-text boundary that identifies a control
≥ 3:1.

## 4 · State colours — the five that already mean something

These are the states the domain has. Each gets **three** signals, in this order of authority.
Colour is signal three and is allowed to be lost.

| state | word on screen (de) | 1 · word | 2 · texture / ink | 3 · tint token |
|---|---|---|---|---|
| **open / running** | „Läuft — seit 08:15" | `Status` column badge + a sentence naming the start time | none (a running shift is normal) | `--state-open` = accent family, `--accent-soft` / `--accent-ink` |
| **auto-closed, unresolved** | „Automatisch beendet — noch nicht geprüft" | badge + sentence naming the 8h rule in plain words | 135° stripe on the row (`.row-attention`) | `--state-caution` = `--caution-soft` / `--caution-ink` / `--caution` border |
| **corrected / amended** | „Korrigiert — war 08:15, jetzt 08:30" | badge + sentence carrying **both** values | `600` weight on the changed cell | `--state-amended` = `#efe6fa` / `#45297a` (**9.38**) |
| **inactive** | „Inaktiv" | badge + the only remaining action is „Wieder aktivieren" | 135° stripe (`.row-inactive`) + `--ink-muted` | `--state-inert` = `--bg-sunken` / `--ink-muted` |
| **excluded from payroll** | „Nicht in der Lohnabrechnung — offene Schicht" | badge **and** the money cell renders `—`, never `0,00 €` | `line-through` on the excluded amount if a figure is shown at all | `--state-inert` |

Hard rules for these five:
- A silent zero is forbidden. An excluded amount is `—` plus a sentence, because `0,00 €` in
  a payroll column is a claim, and a wrong one.
- „Korrigiert" must print the old value. A correction that hides what it replaced is not an
  audit trail (decision-30).
- The badge is bordered and labelled — it must be legible with `background: none` forced.
  Existing `.shift-state` / `.material-stage-*` construction already does this; keep it.
- Material lifecycle (`decide/order/deliver/done/refused`) maps onto the same five: `decide`
  → caution, `order`/`deliver` → open, `done`/`refused` → inert (`refused` keeps its
  `line-through`, which is the word „endgültig" made visible).

## 5 · Radii and elevation

```
--radius-sm:   4px    code chips, focus-ring rounding
--radius-md:   6px    buttons, inputs, selects, nav links, notices
--radius-lg:  10px    cards, tables, panels, phone row-cards
--radius-pill: 999px  state badges
```
Four values. Anything else is a bug.

**Elevation: three levels, and level 2 is nearly unused.**

| level | recipe | used by |
|---|---|---|
| e0 | nothing | page background, table rows |
| e1 | `1px solid var(--border-subtle)` — **no shadow** | every card, panel, table, callout, filter bar |
| e2 | `1px solid var(--border-subtle)` + `--shadow-float: 0 2px 6px rgba(22,25,29,.18)` | only things that overlay content: `.nav-tooltip`, a sticky `thead` once it has scrolled |

Never shadow a button, a card, an input or a badge. Rationale: this is a document-shaped
admin on a light grey field; a shadow adds no information and renders as grey mush on the
cheap phone screens decision-28 exists for. Depth here is carried by border + surface.

## 6 · The component set — eleven, derived from the audit

For each: **anatomy · states · a11y contract**. Existing class names in `code`.

### 6.1 `.data-state` — loading / empty / error+retry  ⟵ finding 1, finding 8

The missing component. One region per data-backed section, four mutually exclusive branches.

- **Anatomy** — `<div class="data-state">`: headline (one sentence, plain German) · optional
  explanation · optional action row. Never a spinner, never a skeleton: the truth is a word.
- **States**
  - `loading` — „Daten werden geladen…". Nothing else on the page pretends to be data.
  - `empty-true` — the set really is empty: says so, **plus the next action**
    („Ersten Mitarbeiter anlegen"), never a congratulation. „Nichts zu tun" over an empty
    database is a lie (finding 8).
  - `empty-filtered` — rows exist outside the filter: says how many, names the newest date,
    offers two one-click escapes. **The `/shifts/` implementation is the reference — copy
    it, do not reinvent it** (audit §4, „handled well").
  - `error` — `--danger` ink, states what failed in plain words, **always** a „Erneut
    versuchen" button. Loading text must be gone.
- **a11y**
  - Container `role="status" aria-live="polite"` and **always in the DOM** (`:empty` stays
    rendered — the existing `.form-error` comment is right and generalises here).
  - The `error` branch uses `role="alert"` on the message only, once, and does **not** move
    focus. The retry button is the first focusable element in the region.
  - The retry button is a real `<button type="button">`, min 44px on coarse pointers.
  - `aria-busy="true"` on the region while loading; removed on settle.

### 6.2 `.button-primary` / `.button-secondary` / `.button-danger` / `.button-row`

- **Anatomy** — text only, no icon-only buttons anywhere in this panel. No fixed width; a
  German label grows the button and may wrap to two lines.
- **States** — default · `:hover` (fill → `--accent-hover`, secondary → `--accent-soft`) ·
  `:focus-visible` (3px `--border-focus`, offset 2, **never removed on hover**) · `:active`
  (`translateY(1px)`, no shadow) · `:disabled` (`opacity .6`, `cursor: not-allowed` — today's
  `cursor: progress` lies about half the cases) · `loading` (label swaps to a progress verb,
  `aria-busy`, stays the same box).
- `.button-danger` is new and mandatory for the two unconfirmed destructive actions the audit
  found („Ablehnen" is terminal, „Periode rückgängig machen" rewrites a reported month).
  Destructive actions get `--danger` fill **and** a confirm step; colour alone is not consent.
- `.button-row` — `display:flex; flex-wrap: wrap; gap: var(--space-2)`. This replaces
  `.cell-actions { white-space: nowrap }`, which is the direct cause of the button/sentence
  overlap on `analytics-map-nokey-1280.png`. Wrapping in a table cell is fine; overlapping is
  not. `.cell-actions` keeps its `display: table-cell` — never `display: flex` on a `<td>`
  (existing comment is correct: it drops the cell's role).
- **a11y** — accessible name is the visible label; `disabled` buttons still need a reason in
  adjacent text; no `title`-only affordances.

### 6.3 `.field` — input / select / textarea / checkbox

Anatomy unchanged: `label` (600, `--text-sm`) → control → `.field-hint` → `.field-error`.

- Control border `--border-strong` (3:1), `--radius-md`, `--text-base`, padding
  `--space-2 --space-3`, `min-height: 44px` on coarse pointers.
- `:focus-visible` ring as global. Invalid: `border-color: var(--danger)` **and**
  `aria-invalid="true"` **and** the message text — three signals.
- Hint and error boxes stay in the DOM when empty (live region survives; already documented
  in the file and correct).
- **a11y** — `aria-describedby` chains hint + error; `aria-invalid` on the control, never on
  the wrapper; checkbox label is clickable and ≥44px on coarse.

### 6.4 `.data-table` — desktop table ⟷ phone cards  ⟵ findings 3, 7

The load-bearing component. Two shapes, one markup.

- **Anatomy** — `caption` (visually hidden allowed) · `thead th[scope=col]` ·
  `tbody tr > th[scope=row]` first (the card title on phone) · `td` · `tfoot` totals.
- **Desktop (≥768px)**
  - `overflow-wrap: break-word` + `hyphens: auto`, **never `anywhere`** (`anywhere`
    contributes to min-content width → 1.95× measured text-width loss, finding 3).
  - `.col-numeric` cells: `white-space: nowrap`, `text-align: right`, `tabular-nums`,
    reserved min-width (§9).
  - Identifier cells (`.code-block`, `.code-inline`) keep `overflow-wrap: anywhere` — a UUID
    has no break opportunity and must never overflow. Scope it to the chip, not the cell.
  - `thead th` `--text-sm`, `--ink-muted`, uppercase, `letter-spacing .04em`.
  - Optional: `position: sticky; top: 0` on `thead th` with e2 shadow once scrolled.
- **Phone (<768px, decision-28)** — existing card transform stays, with two fixes:
  - `tfoot` cells get `data-label` too (finding 7 — `ResponsiveTableLabels` only walks
    `tbody tr`). Four unlabelled numbers is the row a director reads down the phone.
  - Badge text may wrap inside a card (`white-space: normal`); it stays `nowrap` in a table.
- **States** — `.row-attention` (caution stripe) · `.row-inactive` (inert stripe + muted) ·
  `:hover` on a row: **none** (rows are not clickable here; a hover highlight would promise a
  click that does not exist) · empty table → never rendered, `.data-state` renders instead.
- **a11y** — real `<table>` semantics at both widths. `thead` is visually hidden on phone,
  **never `display:none`**. `scope` on every header. No `display:flex` on `td` at desktop.
  `data-label` correctness is a checked property, not a hope (§11).

### 6.5 `.shift-state` — state badge (also `.material-stage-*`)

- **Anatomy** — bordered pill, `--radius-pill`, `--text-sm`, weight 600, word inside.
  Optional `.shift-state-note` sentence beneath, `--text-sm`, `--ink-muted`.
- **States** — the five in §4, plus `complete` (inert). No interactive states: a badge is not
  a button and never gets `cursor: pointer`.
- **a11y** — plain text, no `role`, no `title`. If a badge's meaning needs more than its word,
  the extra words go in the visible note, not in an attribute.

### 6.6 `.notice` / `.callout` — caveat blocks  ⟵ finding 2

One component, four severities, chosen by what the reader must do.

| severity | left border / bg | when |
|---|---|---|
| `info` | `--accent` / `--accent-soft` | standing explanation („so wird gerechnet") |
| `caution` | `--caution` / `--caution-soft` | the number on screen may be incomplete — row cap, unresolved shifts |
| `danger` | `--danger` / `--danger-soft` | the number on screen **is wrong** or an action is irreversible |
| `ok` | `--ok` / `--ok-soft` | a write succeeded |

- The payroll reconciliation caveat is `danger`, and the sign of the difference must be read
  from the data, not hard-coded („zu niedrig" / „zu hoch"), and **the CSV must carry the same
  caveat as a leading comment row** — a file that leaves the warning behind on the screen is
  the highest money risk in the panel (finding 2).
- **Anatomy** — 4px left border, 1px full border, `--radius-lg`, `--space-4 --space-6`,
  optional `h3` at `--text-base`/600, body ≤ 80ch.
- **a11y** — a standing caveat is **not** a live region (it is not news). A caveat that
  appears in response to an action is `role="status"`. Severity is never carried by colour
  alone: the first clause says what it is.

### 6.7 `.disclosure` — create forms fold away  ⟵ finding 9

- **Anatomy** — native `<details><summary>` styled as a secondary button-ish row. No JS, no
  dependency, keyboard and screen reader support for free.
- **Rule** — on a screen whose job is verification (`/shifts/`, `/workers/`, `/locations/`,
  `/inventory/`, `/clients/`) the create form is **collapsed by default** and the list starts
  within the first viewport. Open state persists for the session only if free; do not add
  storage for it.
- **States** — closed · open · `:focus-visible` on `summary` · disabled: n/a.
- **a11y** — `summary` is the accessible name („Mitarbeiter anlegen"); do not add
  `aria-expanded` (the element provides it); never nest a form control inside `summary`.

### 6.8 `.panel` — page section card

Unifies `.worker-form`, `.auth-card`, `.contract-panel`, `.building-panel`, `.share-panel`,
`.filter-bar`. Same recipe: `--bg-surface`, e1, `--radius-lg`, `--space-6`.

- **States** — `:focus-visible` outline when focus is moved into it programmatically
  (existing behaviour on the two detail panels; keep).
- **a11y** — a panel that is a landmark gets a heading and `aria-labelledby`; a panel focus is
  moved into gets `tabindex="-1"` and a visible outline. Never a focus trap: the client-link
  panel must stay copyable and readable in place.

### 6.9 `.panel-metrics` / `.page-summary` — the number sheet

- `<dl>` two columns, `auto 1fr`, term `--ink-muted`/600. Values are `.num` (§9).
- `.page-summary` is `--text-md`/600 and `role="status"` — it changes when the period changes.
- **a11y** — `dt`/`dd` pairing is the accessible relationship; do not fake it with divs.

### 6.10 Shell: `.app-shell`, `.sidebar`, `.nav-link`, `.skip-link`, `.nav-tooltip`

Unchanged in structure. Deltas only:
- Delete `--desktop-min` — dead since decision-28 removed the blocker.
- `.nav-tooltip` is the only e2 element in normal use; it is already a real DOM node exposed
  via `aria-describedby` and hidden on phones. Keep.
- `.nav-link[aria-current="page"]`: tint **and** weight 600 — the pair, not either alone.

### 6.11 `.code-inline` / `.code-block` — identifiers

Unchanged and correct: monospace, `--bg-sunken`, `--radius-sm`, `user-select: all` on the
block, never truncated with an ellipsis. This is the one place `overflow-wrap: anywhere`
is right, and it must be scoped **to the chip**, not inherited by the table cell.

**Not in the set, on purpose:** modal/dialog, toast, tabs, accordion (beyond `<details>`),
icon button, avatar, spinner, skeleton, drawer, carousel. None is needed by any of the twelve
routes; each would be a new state machine to get wrong.

## 7 · Animation — baseline tier

Motion here is for **continuity and feedback**, never delight. Two durations, one easing,
one property pair.

```
--motion-fast: 120ms    hover, focus, tooltip, button press
--motion-base: 160ms    disclosure open/close, panel enter
--ease-out: cubic-bezier(0.2, 0, 0, 1)
```

- **Only `opacity` and `transform` animate.** No `width`, `height`, `top`, `background`,
  `color`, `box-shadow` transitions — they either cost layout or fight the card transform.
- **Maximum travel 8px**, 4px preferred. Nothing slides in from off-screen.
- What may move, exhaustively:
  | element | motion |
  |---|---|
  | `.skip-link` | `top` on focus — the one exception, it is already there and it is a jump not a slide; may become `transform: translateY` |
  | `.nav-tooltip` | opacity 0→1, `--motion-fast` |
  | `.button-*:active` | `translateY(1px)`, no transition (instant) |
  | `<details>` content | opacity + `translateY(-4px)`→0, `--motion-base` |
  | `.data-state` → content | opacity 0→1, `--motion-fast`, **only on first settle** |

- **Never animates**, and this list is normative:
  - **any number** — no count-up, no ticker. A number that animates is a number being read
    while it is wrong.
  - table rows on data change, filter change, sort or reorder
  - anything in an error path: `role="alert"` content appears **instantly**; a fade on bad
    news is a delay on bad news
  - state badges changing state (colour transitions hide the change)
  - page/route transitions, the map, the sidebar strip, focus rings, row stripes
  - anything with `position: sticky`
- **`prefers-reduced-motion: reduce` → everything off.** Not „shorter" — off. None of the
  motion above carries information, so removing it costs nothing:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```
This is the one `!important` block in the file, and it is justified: it must beat every
author rule including future ones. It also replaces the current hand-maintained
`@media (prefers-reduced-motion)` list of two selectors, which is a list that will silently
fall out of date the next time somebody adds a transition.

## 8 · German-specific rules

- No `white-space: nowrap` on anything holding a translated string. Present exceptions to
  fix: `.cell-actions`, `.shift-state` inside a phone card, `.data-table tfoot td`.
- `hyphens: auto` on prose + cells; relies on `<html lang="de">` (already correct).
- Buttons and nav links may wrap to two lines and grow their box.
- Column headers wrap; they never rotate, never truncate, never get a tooltip.
- Test every screen at **390px in German**, not English. „Materialanforderungen" is 22
  characters; „Material requests" is 17.

## 9 · Density and numbers

The panel's job is money and hours. This section is a hard contract.

**Alignment**
- `font-variant-numeric: tabular-nums` on the whole `.data-table` and on a `.num` utility for
  numbers outside tables (`.page-summary`, `.panel-metrics dd`, callout figures). Today only
  `.col-numeric` has it, and the money in callouts and summaries does not.
- Money and hours: `text-align: right` in tables, `white-space: nowrap`,
  `overflow-wrap: normal`. The `€` is joined with a **non-breaking space** (`1.234,50 €`),
  so the symbol can never orphan onto its own line.
- Money is integer cents formatted `de-AT` with **always two decimals**. Hours are integer
  minutes formatted `H:MM`, minutes always two digits. No „ca.", no rounding to hours.

**No reflow between states.** A cell must be the same width whether it says `—`, `0,00 €` or
`121.334,00 €`. Reserve it:

```
--col-money: 11ch    up to  999.999,99 €
--col-hours:  6ch    up to  9999:59
--col-pct:    7ch    up to    -99,9 %
```
Applied as `min-width` on the `th` **and** the `td` of a numeric column. A missing value
renders `—` (em dash), right-aligned, `--ink-muted`, with the reason in the note beneath —
never blank, never `0`.

**Row density**

| context | vertical padding | why |
|---|---|---|
| data table ≥768px | `0.375rem` (6px) | 20+ rows on one screen; `--leading-dense` keeps two-line German legible |
| phone card row | `--space-2` (8px) | thumb-scanned, and each row is one label+value pair |
| form field | `--space-2 --space-3` | 44px min target |

Cells stay `vertical-align: top`: a two-line German label must not push its numeric neighbour
off the baseline.

## 10 · Diff sketch — `web/app/globals.css`

**Not applied.** Token block plus the eight rule deltas that carry the findings. Everything
not shown stays as it is.

```diff
@@ web/app/globals.css:1
-/*
- * Desktop-first (decision-7). No mobile layout exists; below --desktop-min the whole admin UI
- * is swapped for the blocker.
+/*
+ * One stylesheet, no framework, no dependency (decision-16). Tokens below are the whole
+ * design system; backlog/docs/DESIGN-SYSTEM.md is the prose. Phone-capable per decision-28.
  *
- * German runs ~30% longer than English (decision-8). Rule for every rule in this file: size
- * boxes by content, never by a magic pixel width. `ch`/`rem` + wrapping, no `white-space:
- * nowrap` on anything that holds a translated string, no fixed-width buttons.
+ * German runs ~30% longer than English (decision-8). Size boxes by content, never by a magic
+ * pixel width: `ch`/`rem` + wrapping + `hyphens: auto`, no `white-space: nowrap` on anything
+ * holding a translated string, no fixed-width buttons, and NEVER `overflow-wrap: anywhere`
+ * on a table cell — `anywhere` contributes to min-content width and crushes every text
+ * column to 1ch (measured 1.95x, UX-AUDIT finding 3). `break-word` does not.
  */

 :root {
-  --desktop-min: 1024px;
+  /* --desktop-min deleted: the blocker is gone (decision-28). */
   --sidebar-w: clamp(13rem, 16vw, 19rem);

-  --bg: #f6f7f9;
-  --surface: #ffffff;
-  --border: #d8dce3;
-  --ink: #16191d;
-  --ink-muted: #5b6472;
-  --accent: #1f5aa6;
-  --accent-soft: #e8f0fa;
-  --focus: #0b63d6;
+  /* --- Surfaces + ink. Ratios measured against the surface they sit on. --------------- */
+  --bg-app: #f6f7f9;
+  --bg-surface: #ffffff;
+  --bg-sunken: #f6f7f9;
+  --ink: #16191d;             /* 17.6:1 */
+  --ink-muted: #5b6472;       /*  5.98:1 — the floor for any real text */
+  --ink-inverse: #ffffff;
+
+  /* Decorative rules vs the boundary of a CONTROL. The second must clear 3:1 (WCAG 1.4.11);
+     #d8dce3 is 1.38:1 and was doing both jobs. */
+  --border-subtle: #d8dce3;
+  --border-strong: #868d97;   /*  3.35:1 on surface, 3.12:1 on app */
+  --border-focus: #0b63d6;
+
+  /* --- Action ------------------------------------------------------------------------ */
+  --accent: #1f5aa6;          /*  6.84:1 */
+  --accent-hover: #17457f;
+  --accent-soft: #e8f0fa;
+  --accent-ink: #14406f;      /*  9.17:1 on --accent-soft */
+
+  /* --- Feedback. Severity = what the reader must DO, not how loud it is. -------------- */
+  --danger: #a4262c;          /*  7.26:1 */
+  --danger-soft: #fdeaea;
+  --caution: #8a5a00;         /*  5.93:1 */
+  --caution-soft: #fdf0d5;
+  --caution-ink: #6b4400;     /*  7.59:1 on --caution-soft */
+  --ok: #1c6b3c;              /*  6.53:1 */
+  --ok-soft: #e7f4ec;
+
+  /* --- Domain states. Word first, texture second, tint third (DESIGN-SYSTEM §4). ------ */
+  --state-open-bg: var(--accent-soft);
+  --state-open-ink: var(--accent-ink);
+  --state-caution-bg: var(--caution-soft);
+  --state-caution-ink: var(--caution-ink);
+  --state-amended-bg: #efe6fa;
+  --state-amended-ink: #45297a;   /* 9.38:1 */
+  --state-inert-bg: var(--bg-sunken);
+  --state-inert-ink: var(--ink-muted);
+
+  /* --- Type. Six sizes, 12px floor. -------------------------------------------------- */
+  --text-xs: 0.75rem;
+  --text-sm: 0.875rem;
+  --text-base: 1rem;
+  --text-md: 1.125rem;
+  --text-lg: 1.375rem;
+  --text-xl: 1.75rem;
+  --leading-tight: 1.25;
+  --leading-dense: 1.4;
+  --leading-body: 1.55;

   --space-1: 0.25rem;
   --space-2: 0.5rem;
   --space-3: 0.75rem;
   --space-4: 1rem;
   --space-6: 1.5rem;
   --space-8: 2rem;
+  --row-y: var(--space-2);        /* tightened to 0.375rem for tables >=768px */
+
+  /* --- Radii + elevation. Four radii; shadow ONLY for things that overlay content. ---- */
+  --radius-sm: 4px;
+  --radius-md: 6px;
+  --radius-lg: 10px;
+  --radius-pill: 999px;
+  --shadow-float: 0 2px 6px rgba(22, 25, 29, 0.18);
+
+  /* --- Numeric column widths: a cell is the same width for "—" and "121.334,00 €". ---- */
+  --col-money: 11ch;
+  --col-hours: 6ch;
+  --col-pct: 7ch;
+
+  /* --- Motion: two durations, one easing, opacity+transform only. -------------------- */
+  --motion-fast: 120ms;
+  --motion-base: 160ms;
+  --ease-out: cubic-bezier(0.2, 0, 0, 1);
 }
+
+/* Old names kept as aliases for ONE change: the eleven screens reference --bg/--surface/
+   --border/--focus in ~200 places and renaming them in the same commit as the token block
+   makes the diff unreviewable. Delete this block in the follow-up commit that renames the
+   usages; `check-design-tokens.mjs` fails once it is empty and a usage remains.
+   ponytail: two commits instead of one, on purpose. */
+:root {
+  --bg: var(--bg-app);
+  --surface: var(--bg-surface);
+  --border: var(--border-subtle);
+  --focus: var(--border-focus);
+}
```

```diff
@@ finding 3 — the single most damaging line in the file
 .data-table th,
 .data-table td {
-  padding: var(--space-2) var(--space-3);
+  padding: var(--row-y) var(--space-3);
   text-align: left;
   vertical-align: top;
   border-bottom: 1px solid var(--border-subtle);
-  /* Long German compounds and long relay addresses break rather than overflow. */
-  overflow-wrap: anywhere;
+  /* `break-word`, NOT `anywhere`: `anywhere` counts toward min-content width, so one
+     incompressible cell steals the table and every text column collapses to ~1ch.
+     Hyphenation (html lang=de is set by IntlProvider) is what handles German compounds. */
+  overflow-wrap: break-word;
+  hyphens: auto;
+  line-height: var(--leading-dense);
 }
+
+/* Identifiers are the one thing with no break opportunity — scope `anywhere` to the chip. */
+.code-inline,
+.code-block {
+  overflow-wrap: anywhere;
+  hyphens: none;
+}
```

```diff
@@ §9 — numbers never reflow
 .col-numeric {
   text-align: right;
   font-variant-numeric: tabular-nums;
+  white-space: nowrap;
+  overflow-wrap: normal;
+  min-width: var(--col-money);   /* per-column override: --col-hours / --col-pct */
 }
+
+/* Numbers outside a table: page summary, metric sheet, callout figures. */
+.num,
+.data-table,
+.page-summary,
+.panel-metrics dd {
+  font-variant-numeric: tabular-nums;
+}
```

```diff
@@ 1.4.11 — a control's boundary must clear 3:1
 .field input,
 .field select,
 .field textarea,
 .button-secondary,
 .locale-switcher select {
-  border: 1px solid var(--border);
+  border: 1px solid var(--border-strong);
 }
```

```diff
@@ finding 1 — the state that does not exist yet
+/* Loading, empty, error and content are FOUR MUTUALLY EXCLUSIVE branches of one region.
+   Rendering the error line and then "Wird geladen…" forever is UX-AUDIT finding 1; the CSS
+   cannot prevent it, but nothing here should make it easy either — hence no `.loading`
+   modifier that can coexist with `.data-state-error`. */
+.data-state {
+  padding: var(--space-6);
+  background: var(--bg-surface);
+  border: 1px solid var(--border-subtle);
+  border-radius: var(--radius-lg);
+  max-width: 70ch;
+}
+
+.data-state-error {
+  border-left: 4px solid var(--danger);
+  background: var(--danger-soft);
+}
+
+.data-state p {
+  margin-bottom: var(--space-3);
+}
+
+.data-state .button-row {
+  margin-bottom: 0;
+}
```

```diff
@@ the button/sentence overlap on analytics-map-nokey-1280.png
-/* NOT display:flex — overriding `display` on a <td> drops its table-cell role … */
 .cell-actions {
-  white-space: nowrap;
+  /* Was `nowrap`, which made a wrapping sentence and a button group overlap. Still NOT
+     display:flex — overriding `display` on a <td> drops its table-cell role in the
+     accessibility tree. The inner .button-row does the flexing. */
+  white-space: normal;
 }
+
+.button-row {
+  display: flex;
+  flex-wrap: wrap;
+  gap: var(--space-2);
+}
```

```diff
@@ severities for caveats (finding 2)
+.notice-caution,
+.callout-caution {
+  border-left-color: var(--caution);
+  background: var(--caution-soft);
+  color: var(--caution-ink);
+}
+
+.notice-danger,
+.callout-danger {
+  border-left-color: var(--danger);
+  background: var(--danger-soft);
+}
+
+.notice-ok,
+.callout-ok {
+  border-left-color: var(--ok);
+  background: var(--ok-soft);
+}
```

```diff
@@ motion: replace the hand-maintained two-selector list
-/* Scoped to the only two animated rules in this file, so no !important is needed … */
-@media (prefers-reduced-motion: reduce) {
-  .skip-link,
-  .nav-tooltip {
-    transition: none;
-  }
-}
+/* The one !important block in the file, and it must stay one: a scoped list of the
+   currently-animated selectors silently goes stale the next time somebody adds a
+   transition, and the failure mode is invisible to everyone who does not need it. */
+@media (prefers-reduced-motion: reduce) {
+  *,
+  *::before,
+  *::after {
+    animation-duration: 0.01ms !important;
+    animation-iteration-count: 1 !important;
+    transition-duration: 0.01ms !important;
+    scroll-behavior: auto !important;
+  }
+}
```

```diff
@@ phone block (decision-28): table density + wrapping badges
 @media (max-width: 767px) {
+  .shift-state {
+    white-space: normal;      /* "Automatisch beendet" must wrap inside a 390px card */
+  }
+
   .data-table tfoot th,
   .data-table tfoot td {
     display: inline-block;
     padding: 0;
     border: none;
     white-space: nowrap;
   }
+
+  /* finding 7: the totals row prints its headings too — ResponsiveTableLabels must walk
+     tfoot as well as tbody, and this is the rule that renders what it writes. */
+  .data-table tfoot td[data-label]::before {
+    content: attr(data-label) " ";
+    font-size: var(--text-xs);
+    letter-spacing: 0.04em;
+    text-transform: uppercase;
+    color: var(--ink-muted);
+  }
 }
+
+@media (min-width: 768px) {
+  .data-table {
+    --row-y: 0.375rem;
+  }
+}
```

## 11 · How this gets verified — every check must be provably able to fail

Verification culture: a check whose negative case cannot fail is not a check. Three checks,
all runnable, no framework, no dependency.

**A · `web/scripts/check-design-tokens.mjs`** (~50 lines, node stdlib only, wired into
`pnpm verify`):
1. parse `:root` from `globals.css`
2. assert every `#hex` in the file appears **inside** `:root` — no raw hex in a rule
3. compute WCAG contrast for the pinned pairs in §3 and assert the stated minimums
   (text ≥ 4.5, control boundary ≥ 3.0)
4. assert `overflow-wrap: anywhere` appears **only** in the `.code-inline/.code-block` rule
5. assert no `transition:`/`animation:` targets a property other than `opacity`/`transform`

Rule 2 is RED on today's file (`#a4262c`, `#fdf0d5`, `#5b3a9b`, `#17457f` and six more live
inside rules), so it lands together with step 1 of §12, not before. Ratios in §3 were computed
with the sRGB relative-luminance formula from WCAG 2.1; check A recomputes them rather than
trusting the table.

*Mutation proof required before it is believed:* set `--ink-muted: #9aa1ab` (2.61:1) → check
must go **RED** on rule 3; set `--border-strong: #d8dce3` → **RED** on rule 3; move one hex
into a rule → **RED** on rule 2. Restore → GREEN. Record the RED output in the PR.

**B · `data-label` coverage, extended to `tfoot`** — the audit already counts `tbody`
791/791. Extend the same count to `tfoot` cells and assert `> 0` on `/pl/` and `/payroll/`.
*Mutation proof:* delete the `tfoot` loop from `ResponsiveTableLabels.tsx` → **RED**.

**C · Column-crush regression** — reuse `/tmp/probe.mjs` §A: measure the five text columns on
`/workers/` at 1280px and assert their combined width > 450px. As shipped that is 275px, so
the check is RED on today's code by construction — which is the point. *Mutation proof is
free:* it fails before the fix and passes after.

Not covered by any check and therefore stated plainly: **nothing here has been rendered.**
No screenshot in `docs/media/states/` reflects this document; the numbers are computed
(contrast) or measured from the audit (column widths), not observed on a rebuilt bundle.

## 12 · Order of application, and what is out of scope

Cheapest-first, each independently revertable:

| step | effort | finding it closes |
|---|---|---|
| 1 · token block + aliases (no visual change) | low | none — enables the rest |
| 2 · `overflow-wrap: break-word` + `hyphens` + numeric `nowrap`/min-width | low | 3 |
| 3 · `.cell-actions` wrap + `.button-row` | low | layout collision |
| 4 · `tfoot` `data-label` (component + CSS) | low | 7 |
| 5 · `--border-strong` on controls, reduced-motion block | low | 1.4.11, motion staleness |
| 6 · `.data-state` + adopt on 11 screens | **med** | 1, 8 |
| 7 · `.disclosure` on the five create forms | med | 9 |
| 8 · callout severities + payroll caveat rewrite + CSV caveat row | med | 2 |

Steps 6–8 change TSX on every screen and each needs its own task; 1–5 are one CSS commit plus
fifteen lines of `ResponsiveTableLabels`.

**Out of scope of this document:** the wrong numbers themselves (findings 2 backend half, 6),
the dead Maps key (4), Sentry (5), ADR ids in copy (10). Those are logic and config, not
design; the system here only guarantees that when they are fixed there is a correct place to
say so.
