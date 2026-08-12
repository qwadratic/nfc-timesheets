# Information architecture and jobs to be done — the admin panel

Date: 2026-08-12 · Scope: `web/app/**` route structure, navigation, deep links, empty states.
**Spec only. No code changed.**

Companion to `backlog/docs/UX-AUDIT.md` (what is broken) — this is *what the shape should be*.
The audit's findings 1, 8, 9 and the „links out / should link and does not" column of its route
inventory are the direct inputs.

Binding constraints, restated because every proposal below obeys them:

- `output: 'export'` (decision-16) → **no dynamic routes.** All deep-link state is query params.
  There is no `/workers/[id]/`. There never will be while the panel is a static export.
- decision-29 → every route works at 390px. Nav must survive being a phone nav.
- decision-8/17 → German default, en/de exact key parity. Every string below is a key, not a literal.
- Money integer cents, time integer minutes, Vienna wall clock. Periods are half-open `[from, to)`
  Vienna midnights (`web/lib/period.ts`) — that vocabulary is already right and is not reopened here.

---

## 1 · Jobs to be done — the director

Ranked **frequency × consequence**. Frequency is per month at pilot scale and at the rollout scale
the board is planning for (~20 cleaners). Consequence is what it costs when the job cannot be done.

The four grounding events are not hypothetical. They are the ones decision-29 records from the
first fortnight of real use, plus the month-end check:

```
a worker could not clock out          → JTBD-2
a cleaner needed an invite on the spot → JTBD-3
a tag did not register                 → JTBD-4
month-end pay had to be checked        → JTBD-5
```

| # | Job (director's voice) | freq/mo pilot → rollout | consequence | score | evidence |
|---|---|---|---|---|---|
| **1** | „Muss ich heute etwas tun?" — scan for exceptions before they compound | 20 → 25 | med — every ignored exception lands on a payslip | **highest** | the panel's landing page; audit finding 8 says it currently answers „nein" to an empty DB |
| **2** | „Diese Schicht steht offen — schließ sie richtig" | 2 → 15 | **high** — unpaid or 8h-stub hours, and decision-10 makes resolution mandatory | **highest** | decision-29 §Context; `nfc-autoclose.timer` fires every 15 min |
| **3** | „Der Neue steht neben mir und muss in fünf Minuten stempeln können" | 0.5 → 3 | **high + time-critical** — a person is standing there, unbillable | high | decision-26 enrolment code, decision-22 SIWA |
| **4** | „Hat der Tap überhaupt funktioniert?" — worker says they tapped, did a row land | 3 → 20 | **high** — otherwise it is the worker's word against nothing | high | decision-29 §Context; UX-AUDIT §1 route table `/shifts/` |
| **5** | „Was zahle ich wem für diesen Monat, und kann ich die Zahl verteidigen?" | 1 → 1 | **highest** — money, an argument with a person, Austrian record-keeping | high | audit finding 2: the CSV can carry a number the screen already knows is wrong |
| **6** | „Wartet gerade jemand in einem Haus auf meine Entscheidung?" — material queue | 1 → 8 | med — a worker is blocked; decision-23 forbids any push, so the panel is the only channel | med | `web/lib/nav.ts` comment; audit: nothing on `/` links here |
| **7** | „Verdiene ich an diesem Objekt Geld?" | 1 → 1 | med-high — pricing decisions, quarterly | med | `/pl/`; audit finding 6 (the total does not add up) |
| **8** | „Brauchen wir dort mehr Zeit als vereinbart?" | 0.5 → 1 | med — renegotiation trigger | med | `/analytics/` Soll/Ist |
| **9** | „Neues Haus, Tag an die Wand, morgen wird geputzt" | 0.3 → 2 | **blocking** when it happens — day one of a client dies here | med | USER-JOURNEYS J1/J3 |
| **10** | „X hört auf — ohne dass Stunden liegen bleiben" | 0.1 → 1 | **high** — USER-JOURNEYS J8 „PARTIAL-TRAP": a leaver with an open shift is silently never paid | low-med | J8 |
| **11** | „Der Stundensatz war falsch — korrigier ihn nachvollziehbar" | 0.1 → 0.5 | **high** — decision-30 requires reason + audit trail | low-med | decision-30 |
| **12** | „Zeig dem Kunden, was bei ihm geputzt wurde" | 0.2 → 2 | low internally, high for trust | low | `/reinigung/`, `lib/portal.ts` |

**What the ranking says about layout.** Jobs 1–4 are all *field* jobs, all *today* jobs, and all
happen on a phone. They are 80 % of the visits and they touch three screens. Jobs 5, 7, 8, 11 are
desk jobs done twelve times a year. The current nav gives both classes the same eleven flat
entries and puts the rarely-used create forms *above* the lists (audit finding 9) — it is
optimised for job 9, the rarest one on the board.

**Jobs that are NOT on this list, deliberately.** „Firmen und Ansprechpartner pflegen"
(`/clients/`) and „Produktkatalog pflegen" (`/inventory/`) are not jobs. Nobody opens the panel to
do them. They are sub-steps of jobs 9 and 6 and they get folded into those screens in §2.

---

## 2 · Route structure derived from the jobs

### The rule used to decide

A path earns a top-level nav slot only if it is **the place a job STARTS**. If it is only ever
reached *in the middle of* another job, it is a tab or a panel, not a route. Eleven flat entries
is not a memory problem because eleven is a big number; it is a memory problem because seven of
them are mid-job destinations presented as starting points.

### Proposed: 7 primary entries in 3 named groups (from 11 flat)

```
HEUTE          /                    Übersicht        job 1
               /shifts/             Schichten        jobs 2, 4, 10
               /material-requests/  Material         job 6

GELD           /payroll/            Lohn             job 5
               /reports/            Auswertung       jobs 7, 8

STAMMDATEN     /workers/            Team             jobs 3, 11
               /locations/          Objekte          jobs 9, 12
```

Three chunks to hold in the head, and the group names map to *when* you are using them: in a
building, at month end, when something changes. Below 768px the groups become three collapsed
sections — the phone nav shows HEUTE expanded, because jobs 1–4 are the phone jobs.

### Route table — every route justified

| route | keep? | job(s) | one-sentence justification | effort |
|---|---|---|---|---|
| `/` | **keep** | 1 | The only screen whose job is „is anything wrong". Highest-frequency job on the board. | — |
| `/shifts/` | **keep** | 2, 4, 10 | The ledger and the only place to correct it. Three of the top four jobs land here. | — |
| `/material-requests/` | **keep, absorb `/inventory/`** | 6 | A worker is blocked in a building; decision-23 leaves the panel as the only channel. | low |
| `/workers/` | **keep** | 3, 11 | The invite-on-the-spot screen. decision-30's rate history belongs on the person, not on a report. | — |
| `/locations/` | **keep, absorb `/clients/` + `/contracts/`** | 9, 12 | The building is the noun the business is organised around: tag, price, client, portal link. | med |
| `/payroll/` | **keep** | 5 | Highest-consequence job. Must stay a screen of its own so its caveats cannot be lost in a tab switch. | — |
| `/reports/` | **new, replaces `/pl/` + `/analytics/`** | 7, 8 | Both answer „wie läuft dieses Objekt über diesen Zeitraum" with the same two dimensions (building × period). | med |
| `/login/` | keep, non-nav | — | decision-20. Correctly outside the shell. | low |
| `/reinigung/` | keep, non-nav | 12 | decision — client portal, no admin chrome, no path back in. Unchanged. | — |
| `/clients/` | **merge → `/locations/?tab=clients`** | — | Cannot state its own question (§4). A client exists only to own buildings and be invoiced. | — |
| `/contracts/` | **merge → `/locations/?id=…&tab=contract`** | — | The screen already forces „pick a building" as step one. That is a tab wearing a route costume. | — |
| `/inventory/` | **merge → `/material-requests/?tab=catalogue`** | — | The queue is the catalogue's only consumer (audit route table says so). | — |
| `/pl/` | **merge → `/reports/?report=pl`** | 7 | See below. | — |
| `/analytics/` | **merge → `/reports/?report=time`** | 8 | See below. | — |

### Why `/pl/` and `/analytics/` become one screen

They share a period selector, a building dimension, a row per building, and a totals row. The
audit's own „should link and does not" column lists each as the other's missing link. Worse, both
compute labour cost for a building over a period — and audit finding 6 is exactly a labour total
that disagrees with itself. **Two screens computing the same money from the same rows is how the
two numbers drift.** One screen, one computation, a `?report=` switch over the presentation.

`/reports/?report=pl` — Umsatz − Arbeit − Material je Objekt.
`/reports/?report=time` — Sollzeit vs Ist-Zeit je Objekt, plus Trend.

The map moves *out of the top of the screen* into the building detail panel. It cannot draw in
production at all (audit finding 4) and even when it can, it never answers a director question —
it decorates one. A permanently-empty blue box occupying the first fold of a report screen is the
opposite of the „clear answer" rule.

### Bookmarks must not 404

Static export → keep `out/pl/index.html`, `out/analytics/index.html`, `out/clients/index.html`,
`out/contracts/index.html`, `out/inventory/index.html` as four-line client-side redirects that
preserve the query string.

`ponytail:` a `<meta http-equiv="refresh">`-style client redirect page, not a rewrite table and
not a server route. Ceiling: it flashes for one frame and needs JS off to be a dead end. Upgrade
path: a redirect map in the Node static handler if a real 301 is ever wanted.

---

## 3 · Cross-linking

**The requirement:** a link between two screens must carry the CONTEXT the reader already had.
Landing on an unfiltered `/shifts/` after clicking „Schichten dieser Person" is a broken link that
happens to return HTTP 200.

Today the whole panel contains **three** `<Link href="/…">` to another screen plus four on the
dashboard. That is the gap.

### 3.1 Two flavours of period, and which to use

| flavour | params | meaning | use when |
|---|---|---|---|
| **named** | `period=lastMonth` | relative to now, re-resolves every day | „go look at that screen" — browsing |
| **absolute** | `from=…&to=…` ISO instants | frozen half-open range | „**prove this exact number**" — any link out of `/payroll/` or `/reports/` into `/shifts/` |

Precedence: **`from`+`to` win over `period`.** When both ends are present and valid the period
selector shows a „Benutzerdefiniert" chip with a one-click escape back to the named default. A
payroll row linking to the shifts that produced it MUST use absolute — a named period re-resolves
tomorrow and stops reproducing the number the director is standing there defending.

### 3.2 Cross-link map

```
                              ┌──────────────────────────────┐
                              │  /  Übersicht                │
                              └──┬────────┬────────┬─────┬───┘
     offen jetzt ────────────────┘        │        │     └──── erste Schritte (leere DB)
       /shifts/?state=open                │        │            → /workers/  → /locations/
                                          │        │
     unbestätigt ─────────────────────────┘        └──── wartet auf Entscheidung
       /shifts/?state=unresolved                          /material-requests/?status=open
       &period=last30Days

  ┌──────────────┐   Schichten dieser Person    ┌───────────────┐
  │  /workers/   │ ──────────────────────────►  │   /shifts/    │
  │              │   /shifts/?worker=<id>       │               │
  │              │                              │               │
  │              │ ◄──── Person öffnen ──────── │               │
  └──────┬───────┘   /workers/?id=<id>          └───┬───────────┘
         │ Lohn dieser Person                       │ Objekt öffnen
         │ /payroll/?period=lastMonth&worker=<id>   │ /locations/?id=<uuid>
         ▼                                          ▼
  ┌──────────────┐                            ┌───────────────┐
  │  /payroll/   │  Stunden dieser Zeile      │  /locations/  │
  │              │ ─────────────────────────► │               │
  │              │  /shifts/?worker=<id>      │  tab=overview │
  │              │  &from=<iso>&to=<iso>      │  tab=contract │
  │              │        ▲ ABSOLUT           │  tab=tag      │
  │              │  Stundensatz korrigieren   │  tab=portal   │
  │              │  /workers/?id=<id>         │  tab=clients  │
  │              │          &panel=rate       └───┬───────────┘
  └──────┬───────┘                                │ Schichten in diesem Objekt
         │ gleiche Arbeitskosten, andere Sicht    │ /shifts/?location=<uuid>
         ▼                                        │ Zeitauswertung
  ┌──────────────────────────────┐                │ /reports/?report=time&location=<uuid>
  │  /reports/                   │ ◄──────────────┘
  │    ?report=pl                │
  │    ?report=time              │  Arbeit dieser Zeile  → /shifts/?location=<uuid>&from&to
  └──────┬───────────────────────┘  Material dieser Zeile→ /material-requests/?location=<uuid>
         │                                                  &status=all&from&to
         │ Vertrag/Preis dieser Zeile                       ▲ ABSOLUT
         └────────────────────► /locations/?id=<uuid>&tab=contract

  ┌──────────────────────┐  Objekt der Anforderung → /locations/?id=<uuid>
  │ /material-requests/  │  Artikel im Katalog     → /material-requests/?tab=catalogue&item=<id>
  └──────────────────────┘

  jede 401 ──────────────► /login/?next=<pfad>&reason=expired
```

### 3.3 Links that must exist and their German labels

| from | link label (de) | to |
|---|---|---|
| `/` exception „offen jetzt" | „Offene Schichten ansehen" | `/shifts/?state=open` |
| `/` exception „unbestätigt" | „Unbestätigte Schichten klären" | `/shifts/?state=unresolved&period=last30Days` |
| `/` **new** exception | „{n} Materialanforderung(en) warten" | `/material-requests/?status=open` |
| `/` **empty DB** | „Ersten Mitarbeiter anlegen" / „Erstes Objekt anlegen" | `/workers/` · `/locations/` |
| `/workers/` row | „Schichten dieser Person" | `/shifts/?worker=<id>&period=last30Days` |
| `/workers/` row | „Lohn dieser Person" | `/payroll/?period=lastMonth&worker=<id>` |
| `/shifts/` row, worker cell | „Person öffnen" | `/workers/?id=<id>` |
| `/shifts/` row, building cell | „Objekt öffnen" | `/locations/?id=<uuid>` |
| `/shifts/` header | „Diesen Zeitraum abrechnen" | `/payroll/?from=<iso>&to=<iso>` |
| `/locations/` row | „Schichten in diesem Objekt" | `/shifts/?location=<uuid>&period=last30Days` |
| `/locations/` row | „Zeitauswertung" | `/reports/?report=time&location=<uuid>` |
| `/locations/` row | „Preisverlauf" | `/locations/?id=<uuid>&tab=contract` |
| `/payroll/` row | „Diese Stunden nachrechnen" | `/shifts/?worker=<id>&from=<iso>&to=<iso>` |
| `/payroll/` row | „Stundensatz korrigieren" | `/workers/?id=<id>&panel=rate` |
| `/reports/?report=pl` row | „Arbeit nachrechnen" | `/shifts/?location=<uuid>&from=<iso>&to=<iso>` |
| `/reports/?report=pl` row | „Material dieser Zeile" | `/material-requests/?location=<uuid>&status=all&from=<iso>&to=<iso>` |
| `/reports/` row | „Vereinbarter Preis" | `/locations/?id=<uuid>&tab=contract` |
| `/material-requests/` row | „Objekt öffnen" | `/locations/?id=<uuid>` |
| any screen, 401 | (automatic) | `/login/?next=<pfad>&reason=expired` |

### 3.4 Rules that keep cross-links honest

1. **A link that filters must say it filtered.** The target screen renders a removable chip:
   „Gefiltert: Mitarbeiter *Anna K.* · Filter entfernen". Without the chip, an arriving director
   reads a filtered empty table as data loss. This is the same bug as audit finding 8, wearing a
   URL.
2. **Payroll never filters, it highlights.** `/payroll/?worker=<id>` scrolls to and marks that row;
   it does **not** hide the others. A payroll screen showing one person has a `Gesamt` row that is
   a lie, and the `Gesamt` row is what the CSV carries.
3. **A link out of a money screen carries `from`/`to`, never `period`.** §3.1.
4. **Links are `<Link>`/`<a href>`, never `onClick` navigation.** Middle-click, ⌘-click, „open in
   new tab" and „copy link" are how a director keeps two screens side by side at month end.
5. **No param triggers a mutation.** §5.1.

---

## 4 · The „clear answer" rule

Every screen states **one question, in German, in one sentence**, and it is a real question a
director asks out loud. It is rendered on the screen (as the subhead under the `h1`), not only in
this document — a question the user cannot see is a question the designer answered for themselves.

| route | die eine Frage |
|---|---|
| `/` | „Muss ich gerade etwas tun?" |
| `/shifts/` | „Welche Stunden stehen im Buch – und stimmen sie?" |
| `/material-requests/` | „Wartet gerade jemand in einem Haus auf eine Entscheidung von mir?" |
| `/material-requests/?tab=catalogue` | „Was kostet das, was meine Leute anfordern?" |
| `/workers/` | „Wer darf für mich stempeln – und zu welchem Stundensatz?" |
| `/locations/` | „Was ist für dieses Objekt vereinbart – und funktioniert sein Tag?" |
| `/locations/?tab=contract` | „Was war für dieses Objekt wann vereinbart?" |
| `/locations/?tab=clients` | „Wem gehört dieses Objekt, und wen rufe ich dort an?" |
| `/payroll/` | „Was zahle ich wem für diesen Zeitraum?" |
| `/reports/?report=pl` | „Verdiene ich an diesem Objekt Geld?" |
| `/reports/?report=time` | „Brauchen wir für dieses Objekt mehr Zeit als vereinbart?" |
| `/login/` | „Wer sind Sie?" |
| `/reinigung/` | „Wann wurde bei mir zuletzt geputzt?" |

**The screens that failed the test, and were merged in §2:**

| screen | the question it could state | why that fails |
|---|---|---|
| `/clients/` | „Welche Firmen und Ansprechpartner habe ich?" | Nobody opens the panel for this. It is always a sub-step of „neues Objekt anlegen" or „wen rufe ich an". → tab on `/locations/` |
| `/inventory/` | „Welche Produkte habe ich erfasst?" | Only ever asked while deciding a material request. → tab on `/material-requests/` |
| `/contracts/` | „Was war der Preis?" | A property of a building, and the screen already makes you pick a building first. → tab on `/locations/` |
| `/pl/` + `/analytics/` | two questions | Both are „wie läuft Objekt X über Zeitraum Y". Same shape, same inputs, one of them already disagrees with itself. → one `/reports/` |

Applied forward: **a proposed screen that cannot state its question does not get built.**

---

## 5 · URL parameter contract

Static export → query params are the entire deep-link vocabulary. That makes this contract
load-bearing, and it makes bad input a *user-visible* problem rather than a 404.

### 5.1 Global rules

| # | rule | why |
|---|---|---|
| G1 | **A param is a VIEW, never an ACTION.** No param may create, mutate, delete, mint an enrolment code, or download a CSV. | A link in an email, a prefetch, a chat unfurl and a browser history restore all replay the URL. `?panel=rate` opens the panel with the button focused; it never applies a rate. |
| G2 | Unknown param **name** → ignored silently. | Analytics junk (`?fbclid=`) must not break a screen. |
| G3 | Known param, **malformed value** → fall back to the default **and say so**. | Never a blank screen, never a silent lie. |
| G4 | Known param, well-formed but **unknown entity** (`worker=999`, deactivated UUID) → **show everything, unfiltered**, with a banner naming the value. | The dangerous case: a valid-looking filter matching zero rows renders an empty table that is indistinguishable from data loss. This bug already shipped once (audit finding 8). |
| G5 | Any value longer than **64 characters** is malformed by definition. | UUID is 36, an ISO instant is 24. Cheap guard against URL junk reaching the DOM. |
| G6 | Filter changes are written back with `history.replaceState`, not `pushState`. | The URL stays copy-paste-shareable, and Back still means „the screen I came from" — which is the whole point of a context-carrying link. |
| G7 | The screen renders its **loading** state until params are parsed. It must never paint an unfiltered list, or „0 Treffer", before the query string has been read. | Static export hydrates with no params known at build time. A flash of the wrong answer on a money screen is a wrong answer. |
| G8 | Values are lowercase; ids are raw (integer in decimal, UUID canonical 36-char lowercase); everything goes through `encodeURIComponent`. | One spelling per value or the „filtered" chip cannot match. |
| G9 | Absolute range params come as a **pair**. One of `from`/`to` alone is malformed → G3. | A half-specified pay period is how a month-end number goes wrong quietly. |

**G3/G4 banner, both locales, one shared component:**

```
G3  „Der Link enthält einen ungültigen Wert für ‚{param}‘. Es wird die Standardansicht gezeigt."
G4  „Der Filter aus dem Link ({label} ‚{value}‘) ist unbekannt oder nicht mehr aktiv.
     Es werden daher alle Einträge gezeigt – es fehlt nichts."   [Filter entfernen]
```

The „es fehlt nichts" clause is not decoration. It is the sentence that separates *filtered* from
*lost*, and it is the same clause `shifts.emptyOutside` already gets right today.

### 5.2 Per-screen contract

Legend: **def** = value when absent. All params optional.

#### `/` — no parameters

Deliberate. The landing page is identical for every director on every visit; there is nothing to
deep-link *to*, only *from*. Any param here would be a state the exceptions view can already reach.

#### `/shifts/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `worker` | integer ≥ 1, or `all` | `all` | G3 | unknown/inactive id → **G4** |
| `location` | UUID v4 lowercase, or `all` | `all` | G3 | unknown id → **G4** |
| `state` | `all` `open` `unresolved` `auto_closed` `manual` | `all` | G3 | new; the dashboard's three exception links target it |
| `period` | `last30Days` `thisMonth` `lastMonth` `thisQuarter` `thisYear` `all` | `last30Days` | G3 | `web/lib/period.ts:PERIODS` is the authority |
| `from`,`to` | ISO-8601 UTC instant, pair | — | G3/G9 | **wins over `period`** (§3.1) |
| `id` | integer ≥ 1 | — | G3 | scroll to + mark one shift. If it is outside the active filter, widen to `period=all`, keep the mark, and say: „Diese Schicht liegt außerhalb des gewählten Zeitraums – der Zeitraum wurde erweitert." |

#### `/workers/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `id` | integer ≥ 1 | — | G3 | expand that person's card; unknown → **G4** |
| `status` | `active` `inactive` `all` | `active` | G3 | job 10: a leaver must stay findable |
| `panel` | `enrolment` `rate` | — | G3 | ignored unless `id` is present and valid. **Opens** the panel and focuses its button — never mints, never applies (G1). `rate` requires decision-30's reason field before it can submit. |

#### `/locations/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `id` | UUID | — | G3 | selects one building; unknown → **G4** |
| `tab` | `overview` `contract` `tag` `portal` `clients` | `overview` | G3 | `contract`/`tag`/`portal` need `id`; without it fall back to `overview` + G3 banner |
| `month` | `YYYY-MM`, 2020-01 … current+1 | current Vienna month | G3 | the time column's month; the default **must** label itself „laufender Monat, noch nicht vollständig" (audit §4) |
| `client` | UUID | — | G3 | restricts the list to one client's buildings; unknown → **G4** |

#### `/material-requests/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `tab` | `queue` `catalogue` | `queue` | G3 | `catalogue` is the absorbed `/inventory/` |
| `status` | `open` `all` `requested` `approved` `ordered` `delivered` `rejected` | `open` | G3 | lifecycle from `web/lib/materials.ts` |
| `location` | UUID, or `all` | `all` | G3 | unknown → **G4** |
| `from`,`to` | ISO instant pair | — | G3/G9 | used by the P&L material link (§3.3) |
| `id` | integer ≥ 1 | — | G3 | opens that request's detail. Opens only — „Ablehnen" stays a deliberate, confirmed click (G1). |
| `item` | integer ≥ 1 | — | G3 | `tab=catalogue` only; marks one catalogue row |

#### `/payroll/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `period` | `PAYROLL_PERIODS` — **`all` is not one of them** | `lastMonth` | G3 | „alles jemals" is not a pay period |
| `from`,`to` | ISO instant pair | — | G3/G9 | wins over `period`; shows the „Benutzerdefiniert" chip |
| `worker` | integer ≥ 1 | — | G3 | **highlights, does not filter** (§3.4 rule 2). Unknown id → G4 banner, no highlight. |

No param may trigger the CSV download (G1). The CSV is a click, and per audit finding 2 it must
carry the reconciliation caveat with it.

#### `/reports/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `report` | `pl` `time` | `pl` | G3 | the merged `/pl/` and `/analytics/` |
| `period` | `PERIODS` | `lastMonth` | G3 | |
| `from`,`to` | ISO instant pair | — | G3/G9 | wins over `period` |
| `location` | UUID | — | G3 | opens the per-building detail panel; unknown → **G4** |
| `months` | integer 3 … 24 | `6` | G3 | trend length, `report=time` only; ignored with a G3 banner on `report=pl` |

#### `/login/`

| param | values | def | invalid → | notes |
|---|---|---|---|---|
| `next` | a path that **exactly matches one of the seven known admin routes** | `/` | silently `/` | **Open-redirect guard.** Must start with `/`, must not start with `//`, no scheme, no host, ≤ 128 chars, and must be on the allowlist. Anything else → `/`, no banner (do not echo attacker-supplied text). |
| `reason` | `expired` `required` | `required` | default | fixes the audit's „teleported with no explanation": `expired` → „Ihre Sitzung ist abgelaufen. Bitte melden Sie sich erneut an." |

#### `/reinigung/` — unchanged

The portal token stays in the **hash** (`#t=…`, `web/lib/portal.ts:56`), falling back to `?t=`.
Keep it that way: a hash is never sent in a `Referer` header and never reaches a server access log.
No other param. No admin chrome, no path back into the panel.

### 5.3 Implementation shape

`ponytail:` one `web/lib/params.ts` — read `window.location.search` in an effect, validate against
a per-screen schema object, write back with `history.replaceState`. **No new dependency**, and
notably *not* `useSearchParams()`, which in `output: 'export'` drags every consuming page into a
build-time Suspense boundary for no benefit here.

Ceiling: params are unavailable during prerender (hence G7), and Back does not step through
filters. Upgrade path if either becomes a real complaint: `useSearchParams` + `Suspense`, or
`pushState` for filter changes only.

---

## 6 · Empty states

**The rule, in three parts.** It exists because the panel already shipped the failure: an empty
database rendered „Nichts zu tun" plus three vacuous all-clears (audit finding 8).

1. **Never assert an all-clear over an empty set.** „Keine Schicht wartet auf Bestätigung" is
   vacuously true with zero shifts and it reads as „alles in Ordnung". If the underlying set is
   empty, the sentence must say the set is empty.
2. **Three emptinesses, three different components. They must never render the same.**

   | kind | means | must contain |
   |---|---|---|
   | `empty-nothing` | no such record exists at all, in any period | „Es fehlt nichts" + the first-step action |
   | `empty-filtered` | records exist, this filter/period hides them | **how many exist outside**, the date of the newest, and a one-click escape |
   | `error` | the load failed | what failed + **a retry button** — and it must NOT also say „Wird geladen…" |

   The third is audit finding 1 and it is an IA problem, not a copy problem: the loading branch is
   keyed on `data === null`, which a failed load never clears. The fix is a state machine, not a
   string: `type Load<T> = {k:'loading'} | {k:'ready',data:T} | {k:'error',err:E}` — **`null` is
   not a state.** One shared component, all seven screens.
3. **Every empty state offers exactly one primary action.** Not zero (a dead end), not four.

`/shifts/`, `/payroll/` and `/locations/` already do (2) well — `shifts.emptyOutside`,
`payroll.emptyLatestRecorded`, `payroll.emptyJump`. That is the pattern to copy, not to reinvent.

### Per screen

| screen | state | says (de) | offers |
|---|---|---|---|
| `/` | nothing exists at all | „Es ist noch nichts eingerichtet. Das ist kein Fehler – es wurde noch nichts angelegt." | **„Mitarbeiter anlegen"** (primary) + „Objekt anlegen". The three all-clears are **suppressed**, not softened. |
| `/` | setup done, no shift ever | „Alles eingerichtet. Es hat nur noch niemand einen Tag gescannt." | „Tag-URL für ein Objekt anzeigen" → `/locations/?tab=tag` |
| `/` | nothing wrong today | „Nichts zu tun. Zurzeit ist niemand eingestempelt." — **only when workers > 0 and shifts > 0** | „Letzte Schichten ansehen" |
| `/` | load error | „Die Übersicht konnte nicht geladen werden." | **„Erneut versuchen"** |
| `/shifts/` | never any shift | (keep) „Noch keine Schichten erfasst. Eine Schicht erscheint hier, sobald ein Mitarbeiter einen Tag scannt." | „Schicht von Hand erfassen" |
| `/shifts/` | filter hides all | (keep) `emptyOutside` + `emptyLatestRecorded` | „Zeitraum erweitern" + „Filter entfernen" |
| `/shifts/` | error | „Das Schichtprotokoll konnte nicht geladen werden." | **„Erneut versuchen"** |
| `/workers/` | none | „Noch keine Mitarbeiter. Ohne Mitarbeiter kann niemand stempeln." | **„Ersten Mitarbeiter anlegen"** (opens the form — which is now collapsed by default, audit finding 9) |
| `/workers/` | `status=active` empty, inactive exist | „Kein aktiver Mitarbeiter. {n} deaktivierte sind erfasst – es fehlt nichts." | „Auch deaktivierte anzeigen" → `?status=all` |
| `/locations/` | none | „Noch keine Objekte. Die Tag-URL entsteht erst mit dem Objekt." | **„Erstes Objekt anlegen"** |
| `/locations/` | month has no time | (keep) „In {Monat} wurde hier nichts erfasst. Es fehlt nichts." | „Letzten Monat mit Zeit anzeigen" |
| `/locations/?tab=contract` | no contract periods | „Für dieses Objekt ist noch kein Preis hinterlegt. Es erscheint daher in der Auswertung ohne Umsatz." | **„Preis hinterlegen"** |
| `/material-requests/` | queue empty, history exists | (keep) „Es wartet nichts auf Sie. Jede Anforderung wurde entweder geliefert oder abgelehnt." | (keep) „Alle {n} Anforderungen anzeigen" |
| `/material-requests/` | never any request | (keep) „Es wurde noch nie eine Materialanforderung erfasst. Es fehlt nichts – es hat nur noch niemand über die App etwas angefordert." | „Katalog ansehen" → `?tab=catalogue` |
| `/material-requests/?tab=catalogue` | none | „Noch keine Produkte oder Geräte. Ohne Katalog kann niemand etwas anfordern." | **„Erstes Produkt anlegen"** |
| `/payroll/` | period empty, data elsewhere | (keep) `emptyLatestRecorded` + `emptyJump` | „{Zeitraum} anzeigen" |
| `/payroll/` | never any shift | (keep) `emptyNeverRecorded` | „Schicht von Hand erfassen" → `/shifts/` |
| `/payroll/` | error | „Die Lohnabrechnung konnte nicht geladen werden. **Es wurde nichts berechnet und nichts exportiert.**" | **„Erneut versuchen"** — and the CSV button is disabled, visibly |
| `/reports/?report=pl` | no priced building in period | (keep shape) „In diesem Zeitraum ist kein Objekt aktiv und in keinem wurde gearbeitet. Es ist nichts verloren gegangen." | „Objekt anlegen" |
| `/reports/?report=pl` | buildings exist, none priced | „{n} Objekte, aber für keines ist ein Preis hinterlegt. Ohne Preis kann kein Ergebnis berechnet werden." | **„Preis hinterlegen"** → `/locations/?tab=contract` |
| `/reports/?report=time` | no target minutes anywhere | „Für kein Objekt ist eine Sollzeit vereinbart. Ohne Sollzeit gibt es nichts zu vergleichen." | **„Sollzeit hinterlegen"** |
| `/reports/` | error | „Die Auswertung konnte nicht geladen werden." | **„Erneut versuchen"** |
| `/login/` | — | n/a | — |
| `/reinigung/` | no cleaning yet | (keep) „Für dieses Objekt ist noch keine abgeschlossene Reinigung erfasst…" | — (correct: a client has no action) |

### The one sentence that does the work

Every `empty-nothing` and `empty-filtered` string contains **„es fehlt nichts"** or names what
exists outside the filter. Every `error` string contains a verb in the past tense („konnte nicht
geladen werden") and **never** the word „lädt". If a string satisfies neither, it is the bug that
already shipped.

---

## 7 · Proving this shipped

Spec-only, so this section is the acceptance contract for whoever implements it. Per the project's
verification culture: **a check whose negative case cannot fail is not a check.** Each of these
must be shown going RED before it is trusted going GREEN.

| # | check | mutation that must make it FAIL |
|---|---|---|
| V1 | Every route's `<h1>` is followed by its §4 question string | delete one `question` key → parity check + assertion both fail |
| V2 | No screen renders `loading` and `error` simultaneously | force a 500 fixture; assert the „Wird geladen" node is absent. Restore the `data === null` branch → RED |
| V3 | Every screen's error state contains an enabled retry control | remove one retry button → RED (this is audit finding 1; it must be checked on all seven, not one) |
| V4 | G4: `?worker=999999` shows **all** rows plus the banner | make the filter drop unknown ids silently → row count goes to 0 → RED |
| V5 | G1: no param mutates | replay every documented URL against the demo DB (`nfc_demo`, `demo/check-guards.sh` guards it) and diff row counts before/after. Add a `?panel=rate&apply=1` shortcut → RED |
| V6 | `/login/?next=https://evil.example/` lands on `/` | accept any `next` value → RED |
| V7 | Payroll `?worker=<id>` leaves `Gesamt` unchanged | make it filter → total changes → RED |
| V8 | Absolute-range links reproduce the source number | click `/payroll/` row → `/shifts/?from&to`, sum durations, compare to the payroll cell. Swap the link to `period=lastMonth` and run on the 1st of a month → RED |
| V9 | de/en key parity stays 100 % across all new keys | add a key to `de.json` only → `pnpm check` RED |
| V10 | The five merged routes still resolve from a bookmark, query preserved | delete `out/pl/index.html` → RED |

**Not covered here, stated so it is not assumed:** contrast ratios (the audit did not measure them
either), iOS/Android navigation, and whether `/reports/` merging changes any server endpoint —
it should not; `GET /admin/pl` and `GET /admin/analytics` stay two calls behind one screen.

---

## 8 · Summary of proposed changes

| change | jobs served | effort | risk |
|---|---|---|---|
| 11 flat nav entries → 7 in 3 groups | all | low | low — nav only |
| `/clients/` + `/contracts/` → tabs on `/locations/` | 9, 12 | med | med — two screens' forms move |
| `/inventory/` → tab on `/material-requests/` | 6 | low | low |
| `/pl/` + `/analytics/` → `/reports/?report=` | 7, 8 | med | med — but it is what stops the two labour totals drifting |
| Five bookmark-preserving redirect stubs | — | low | low |
| URL param contract + `lib/params.ts` + G3/G4 banner | 4, 5, 7 | med | low |
| 20 context-carrying cross-links (§3.3) | 2, 4, 5, 7 | med | low |
| `Load<T>` state machine replacing `data === null` | all | med | **removes** risk — audit finding 1 |
| Empty-state pass on all seven screens | 1, 9 | med | low |
| Collapse create-forms below the lists (audit finding 9) | 1, 2, 4 | low | low |

Highest value first: **`Load<T>` + retry on all seven screens** (finding 1 is on every screen and
every job), then the **empty-state pass on `/`** (finding 8 — the landing page lies to a new
director), then the **cross-links**, then the merges.

---

*Written 2026-08-12. No code changed, no route added, nothing deployed. Production untouched.*
