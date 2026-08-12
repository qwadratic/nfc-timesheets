# Zones inside a building, and writing tags from the app

Design + plan. **No product code written.** Read against the tree at `861985e`.
Binding decisions read: all 31 in `backlog/decisions/`. Prior work read:
`backlog/docs/BACKLOG-TRIAGE.md`, `backlog/docs/IN-SHIFT-AND-PARITY.md`,
`server/db/migrations/001..005`, `server/routes/app.js`, both `TagLink` implementations,
`android/.../nfc/KnownTags.kt`, `NFCTimeSheets.entitlements`, commit `e4ac6e2`.

---

## 0. The verdict, before the evidence

**Zones**

```
zone = a locations row with parent_id set.  NOT a new table, NOT a new id namespace.
  → tag URI unchanged            ?l=<uuid>, uuid may be a building or a zone
  → both TagLink parsers unchanged      0 lines
  → shifts.location_id unchanged        0 rows migrated, 0 shifts invalidated
  → building = COALESCE(parent_id, id)  one expression, used everywhere money is
depth capped at 1 by a CHECK ∴ a zone list is a LIST, never a tree widget
```

**Tag writing**

```
iOS   writing IS permitted today — via NFCTagReaderSession + formats:["TAG"].
      "TAG" is now the ONLY documented value of that entitlement, and it explicitly
      grants WRITE. NDEF is gone from the docs ∴ e4ac6e2's diagnosis was right.
      ⚠ re-adding the entitlement key is what triggered 90778 last time.
        A build that fails validation blocks EVERY other iOS fix, not just this one.
Android  writing is free of any gatekeeper. Ship there FIRST.
admin mode = a server-minted, single-use, single-location, 15-min token.
             NOT a build flag, NOT a hidden gesture, NOT a local PIN.
             A worker cannot mint one ∴ a worker cannot reach the screen.
capacity  our URL is EXACTLY 64 NDEF bytes (computed below). HOIV's tag holds 46.
          ∴ the "will not fit" branch is not an error — it is tag ADOPTION,
            which is KnownTags.kt upgrade path #1 arriving as a product feature.
verify    read back → run through the SAME TagLink.locationId() the tap path uses.
          Anything else is a tag that fails on a wall.
```

**Recommended order:** zones (server + web) → Android writing → iOS writing spike, isolated
in its own throwaway build. Do **not** put the iOS NFC entitlement in the same build as a
clock-in fix.

---

# PART 1 — ZONES

## 1.1 The arithmetic that decides the model

Before choosing a data model, measure what each choice costs on a tag, because the tag is the
only part of this system that is glued to a wall.

An NDEF URI record with the `https://` abbreviation (prefix code `0x04`), short-record form:

```js
// runnable; no deps. Header = flags + typeLength + payloadLength + 'U' = 4 bytes.
function ndefUriMessageBytes(url) {
  const PREFIXES = ["", "http://www.", "https://www.", "http://", "https://"];
  let code = 0, rest = url;
  for (let i = 1; i < PREFIXES.length; i++)
    if (url.startsWith(PREFIXES[i]) && PREFIXES[i].length > PREFIXES[code].length)
      { code = i; rest = url.slice(PREFIXES[i].length); }
  const payload = 1 + Buffer.byteLength(rest, "utf8");
  return (payload < 256 ? 4 : 7) + payload;
}
```

| URI | NDEF bytes | Ultralight EV1 (46) | NTAG213 (144) |
|---|---|---|---|
| `https://timesheets.exe.xyz/t?l=<uuid>` | **64** | ✗ | ✓ |
| `…/t?l=<uuid>&z=<zone uuid>` | **103** | ✗ | ✓ |

64 confirms the figure already written in `KnownTags.kt` ("our URL needs about 64") — that
comment was an estimate; this is the number.

**What this rules out.** A second UUID parameter costs **+39 bytes, a 61 % increase**. It
fits nothing at or below 128 bytes of NDEF capacity, which is the whole cheap end of the tag
market and includes the one tag actually deployed. It also forces a coordinated change to
two parsers, two check suites and decision-21's wording, for zero gain over reusing `?l=`.

∴ **zones must live in the same identifier namespace as buildings.** That single constraint
determines the model.

## 1.2 The model

```sql
-- migration 006
ALTER TABLE locations
  ADD COLUMN parent_id UUID REFERENCES locations(id),
  ADD COLUMN area_dm2  INTEGER CHECK (area_dm2 > 0),
  ADD COLUMN floor     TEXT;

-- Depth is capped at ONE. A zone's parent must itself be a building.
-- Enforced by trigger, because a CHECK cannot see another row.
CREATE INDEX locations_parent_id_idx ON locations (parent_id);
```

`parent_id IS NULL` ⇒ **building**. `parent_id IS NOT NULL` ⇒ **zone**.
Every row that exists today gets `parent_id = NULL` by definition of `ADD COLUMN`. **The
migration touches no data.**

### Why one table and not `zones`

Climbing the ladder before writing anything:

1. **Needed at all?** Yes — the owner wants time attributable below building level, and m²
   only means something attached to a room.
2. **Already have the shape?** Yes. A zone is *a place a worker taps and spends time in*.
   That is what a `locations` row is. A `zones` table would be `locations` minus four
   columns, plus a second FK on `shifts`, plus a second admin screen, plus a `location_id
   IS NULL XOR zone_id IS NULL` constraint on every shift, plus both parsers learning a
   second id kind.
3. **Minimum code?** One nullable self-FK. `shifts.location_id UUID REFERENCES locations(id)`
   already accepts a zone id the day the row exists.

**`ponytail:` adjacency list with a hard depth cap of 1.** CEILING: no floors-inside-wings,
no recursive rollup, no `ltree`, no closure table. UPGRADE PATH: if a real third level ever
appears, the cap is a trigger and the rollup is one `WITH RECURSIVE` — but do not build it
speculatively, because the *UI* cost of depth ≥ 2 is a tree widget and that is the thing the
brief explicitly forbids.

### Constraints that keep money at the building

`locations` carries `client_id`, `monthly_contract_cents`, `target_minutes_per_month`,
`lat/lng`, `geocode_status`. A zone must inherit, never own, all of them:

```sql
ALTER TABLE locations ADD CONSTRAINT locations_zone_has_no_money CHECK (
  parent_id IS NULL OR (
    client_id IS NULL AND monthly_contract_cents IS NULL
    AND target_minutes_per_month IS NULL AND lat IS NULL AND lng IS NULL));
```

And `location_contracts` must refuse zone rows — decision-30's contract history and
decision-6's pro-rata material split are both **per building**, and a zone-level contract row
would silently double-count revenue. Enforced by trigger (an FK cannot express "…and that row
has `parent_id IS NULL`").

Zones are also skipped by geocoding: a stairwell has no street address, and asking Google for
one burns quota to store `ZERO_RESULTS`.

`slug` stays globally `UNIQUE NOT NULL` — `hoiv-arsenalstrasse-11-stiege-a`. No change.

### Area is an integer

`area_dm2` — square **decimetres**, integer. 1 m² = 100 dm².

Same reasoning as money-in-cents: the director types `12.5` for a toilet and `340` for a
garage, and both must survive a round trip and a division without a float appearing anywhere
near a number the business acts on. `NUMERIC(10,2)` is exact in Postgres but `pg` hands it to
JS as a **string**, so every consumer would parse it and the first one that forgets is a
silent `NaN`. Integer dm² gives 0.01 m² resolution and one transform at the form boundary.

`ponytail:` CEILING: one area figure per zone, no gross/net, no "cleanable area vs. floor
area". UPGRADE PATH: a second integer column when someone can say what the second number is.

## 1.3 What happens to the existing tag

**Nothing. It is not touched, and it must not be.**

The tag at HOIV Arsenalstraße 11 is a Mifare Ultralight EV1, serial `04:A1:A8:52:AE:5C:80`,
adopted by serial in `KnownTags.kt` because its 46 NDEF bytes cannot hold our 64-byte URL. It
maps to location `c3c37d4a-…`, which under this model is a **building** row
(`parent_id IS NULL`) exactly as it is today.

A building keeps its tag for as long as it exists. Zones are **additive**: a zone gets its own
tag *if and when someone puts one on its door*, and a building with four zones and one
entrance tag is a completely valid state that this design must never nag about.

**A zone gets its own tag — same URI format, its own UUID in `?l=`.** No new parameter, no
new record type, no parser change. A zone tag is byte-for-byte the same shape as a building
tag; only the UUID differs. The apps cannot tell them apart and do not need to: the *server*
knows which rows have a parent.

## 1.4 What happens to existing shifts

**Nothing, and this is the load-bearing claim of the whole design.**

Live data at last read: 8 shifts, 4 workers, 1 location. Every one of those `shifts` rows has
`location_id` = the building UUID. After migration 006 that row is still a building, so every
existing shift still resolves, still totals, still prices, still pays.

The failure mode to design against is not data loss — it is **retroactive reinterpretation**.
The moment zones exist there is a temptation to render a building-level shift as
`Zone: (keine)`, and `(keine)` reads as *missing*, i.e. as a defect the director should chase.
It is not a defect. It is a complete, correct record of a whole-building clean.

Rule, and it belongs in the decision record:

> A shift whose `location_id` is a building is labelled **"Gebäude gesamt"** — never
> "(keine Zone)", never an empty cell, never a warning icon. It is a first-class value, not a
> null.

Reports therefore always carry the building total as its own bucket, and the sum of the zone
buckets is **not** expected to equal it. Any report that implies otherwise is wrong.

## 1.5 What a building-level tap means once zones exist

It means **"this worker is working in this building; which part is unrecorded."** It stays a
valid, complete clock-in. It is never an error and never blocks.

Why this is not negotiable: the entrance tag is the one that already works, on the wall, on
the phone in someone's pocket. The single highest-risk change this project could make is to
turn a tap that works today into a tap that asks a question at 06:00 in a cold stairwell. The
triage report already records that the pilot ran once and stopped, and that nobody knows why.

∴ **no zone picker at clock-in.** Not a sheet, not a "which zone?" prompt, not a default. If
the building has zones and the worker taps the entrance, they are clocked into the building.

## 1.6 Zone taps and `auto_closed`

This is the one server behaviour that genuinely changes, and it is a two-line change.

Today (`server/routes/app.js`, and the comment on `closeShift`): the app closes an open shift
with `auto_closed = true` when the worker taps a **different building** without tapping out.
`auto_closed && corrected_at IS NULL` is the "unresolved" predicate that forces the worker
through a resolution screen before payroll sees the shift. That is correct — a shift ended by
walking away is an end time no human confirmed.

Moving between zones **inside the same building** is the opposite: it is a deliberate tap on a
deliberate tag by a person standing in front of it. Flagging it would route a normal working
day through the correction screen several times a shift, and a resolution prompt that fires
constantly is a resolution prompt nobody reads.

```
tap target T while shift S open:
  building(T) == building(S)   → close S auto_closed = FALSE, open new at T   (zone move)
  building(T) != building(S)   → close S auto_closed = TRUE,  open new at T   (unchanged)
  where building(x) = COALESCE(x.parent_id, x.id)
```

Consequences worth stating:

- A shift stays **one row per zone segment**. No `shift_segments` table. The
  `shifts_one_open_per_worker_idx` unique index is untouched and still does its job.
- A day in one building with three zones becomes three shift rows, not one. Payroll already
  sums rows, so pay is unchanged; the **shift list** gets longer and must group by
  building+day in the UI or it will read as noise.
- The decision on `auto_closed` must be made **server-side**, not in the app. The app does not
  know that two UUIDs share a parent, and teaching it would mean shipping the hierarchy to
  every phone and keeping it in sync. Server is authoritative for open shifts (decision-19) —
  this is the same rule applied to one more field.

## 1.7 The m²/hour number — what it is for

```
Flächenleistung = area_dm2 / 100 / (payable_minutes / 60)      m² per hour
```

**What it is for: pricing and planning.** Three questions, all of them about *places*:

1. When quoting a new building, what should a 400 m² stairwell be budgeted at? The answer is
   the historical rate for stairwells we already clean.
2. Which zone is consuming time out of proportion to its size — i.e. where is the contract
   assumption wrong?
3. Did a zone's rate change after we changed the method or the product?

**What it is not for: rating people.** Stated in the decision record in those words, because
the number is one `GROUP BY worker_id` away from being a league table, and someone will write
that query.

## 1.8 How it misleads — and what the design does about each

A warning in a document is not a control. Each row below has a mechanism.

| Failure | Why it happens | Mechanism in the design |
|---|---|---|
| **Assignment bias** — the cleaner given the worst rooms looks slow | area ignores difficulty entirely | m²/h is computed and displayed **per zone**, never per worker. A worker figure may only ever appear *inside* a single zone, against that zone's own median |
| **Area ≠ effort** | 40 m² of open office ≠ 40 m² of stairwell with 60 steps and a handrail | never compare across zones. The default comparison is **a zone against its own history** |
| **n = 1** | one shift is not a rate | every rate renders with its shift count. Below **5 shifts** the panel shows `n = 3 — zu wenig Daten` and **no number at all**. Suppression, not a caveat next to a number |
| **Unconfirmed end times** | the 8h auto-close (decision-10) invents a denominator | shifts with `auto_closed AND corrected_at IS NULL` are **excluded** from productivity. They are already excluded from payroll; the two must not disagree |
| **Missed zone taps** | worker forgets to tap zone B → zone A's time balloons, zone B vanishes | a segment longer than **3×** the zone's median is excluded and counted as `unplausibel`, with the count shown. The exclusion is visible or it is a lie |
| **Rollup paradox** | building m²/h computed from summed areas hides a zone that got worse | the building figure is shown **beside** the zone rows, never instead of them |
| **Area is a guess** | nobody measured the stairwell | `area_dm2` is NULLable and a zone without it is simply absent from productivity, never treated as 0 m² |

The single most important of these is the first, and it is a **product** rule, not a
statistical one: there is no per-worker productivity screen, and no export that produces one
by accident. If the owner later asks for one, that is a new decision record with this table
attached to it.

## 1.9 UI — and how it stays out of the director's way

**The rule: a director who never uses zones must see one line of new chrome, forever.**

**`/locations` (Objekte) — the list does not change shape.**
`WHERE parent_id IS NULL`. Same flat table, same columns, plus one:

```
Objekt                    Kunde     Bereiche   Vertrag
HOIV Arsenalstraße 11     HOIV          —      1.200,00 €
Musterhaus 4              …             3      …
```

`—` when a building has no zones. Not `0` — a zero invites the reading "you should add some".

**The building detail page grows one section, below the existing fields.**

```
Bereiche                                              [ + Bereich ]
──────────────────────────────────────────────────────────────────
Stiege A          Fläche 120,0 m²   Stock EG      Tag ✓   [Bearbeiten]
Büro 1. OG        Fläche  85,5 m²   Stock 1. OG   Tag —   [Bearbeiten]
```

A flat table. Not a tree, not an expander, not drag-to-reorder. **This is only honest because
depth is capped at 1** — the cap is what buys the flat UI, which is why it is a database
constraint and not a convention.

Zero zones ⇒ the section is a heading and one button. That is the entire cost to a director
who does not want this feature.

**Where zones do NOT appear:** the sidebar (no `nav.zones` entry — a zone is never a
destination), the dashboard, the payroll screen, the P&L. A zone is a property of a building,
so it lives on the building.

**Shifts list:** one new column `Bereich`, showing the zone name or **`Gebäude gesamt`**
(§1.4). Rows group by building + day so three zone segments read as one working visit.

**Mobile (decision-29):** the zone table is a `.data-table` and gets labelled cards below
768 px through `components/ResponsiveTableLabels.tsx`. No new mechanism. The `+ Bereich`
button is a 48 px target.

**Accessibility:** `Tag ✓ / —` is an icon *plus* a text label, never colour alone; the area
input is `<input type="number" inputmode="decimal">` with the unit in the visible label
(`Fläche (m²)`) and not as placeholder text; the zone table has a `<caption>` naming its
building, because a screen-reader user arriving at a second table on the page must be told
which one it is.

**Strings.** New namespace `zones.*` in `web/messages/{de,en}.json`, exact key parity
(`pnpm check` already enforces it). German is the shipped default:

| key | de | en |
|---|---|---|
| `zones.section` | Bereiche | Zones |
| `zones.add` | Bereich hinzufügen | Add zone |
| `zones.area` | Fläche (m²) | Area (m²) |
| `zones.floor` | Stock | Floor |
| `zones.wholeBuilding` | Gebäude gesamt | Whole building |
| `zones.none` | — | — |
| `zones.rate` | Flächenleistung (m²/h) | Area rate (m²/h) |
| `zones.tooFewShifts` | zu wenig Daten | not enough data |

`Bereich`, not `Zone`: `Objekt` is already the building in this panel's German, and `Bereich`
is the ordinary Austrian trade word for a part of one. `floor` is **TEXT** — Austrian floors
are `EG`, `1. OG`, `Keller`, `Souterrain`, not integers.

## 1.10 Deliberately not built

Named so nobody has to guess whether it was forgotten.

- **No zone-level contracts or pricing.** Money stays at the building (decision-6, decision-30).
- **No zone taxonomy** (`kind`: stairwell / office / sanitary). Two consumers would be needed
  to justify it and there are zero. `note TEXT` covers it until a report wants to group by it.
- **No per-worker productivity screen.** §1.8.
- **No cleaning schedule / rota per zone.** Different feature, different backlog item.
- **No zone hierarchy beyond one level.** §1.2.
- **No zone picker in either app.** §1.5. The apps stay unaware that zones exist — they see
  location UUIDs, which is all they have ever seen.

---

# PART 2 — WRITING TAGS FROM THE APP

## 2.1 iOS: exactly what is permitted now

**Fetched from Apple's live documentation while writing this.**

### The entitlement

`com.apple.developer.nfc.readersession.formats` — "Near Field Communication Tag Reader Session
Formats Entitlement", `iOS 11.0+`. Its **Possible Values** section today lists **one** value:

> `TAG`
> Allows read and write access to a tag using `NFCTagReaderSession`.
> — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats

`NDEF` is **no longer a documented value of this entitlement.** That is the direct corroboration
of commit `e4ac6e2` and App Store error 90778 ("NDEF is disallowed … TAG is missing in the
entitlement"). The commit's diagnosis was right and its ceiling note was right:

> "if background tap proves unreliable on real hardware, the fallback is
> `NFCTagReaderSession` + 'TAG', not the old NDEF session."

### Writing is permitted, and this is the exact path

`NFCTagReaderSession` — "A reader session for detecting ISO7816, ISO15693, FeliCa, and MIFARE
tags", `iOS 13.0+`. Its Overview states the two requirements and nothing else:

> "To use this reader session, you must:
> - Include the Near Field Communication Tag Reader Session Formats Entitlement in your app.
> - Provide a non-empty string for the `NFCReaderUsageDescription` key in your app's
>   information property list file."
> — https://developer.apple.com/documentation/corenfc/nfctagreadersession

`NFCTagReaderSession` hands the delegate an `NFCTag` enum case; for a Mifare Ultralight EV1
that is `.miFare(NFCMiFareTag)`. And per the `NFCNDEFTag` documentation, its **Inherited By**
list is exactly:

> `NFCFeliCaTag`, `NFCISO15693Tag`, `NFCISO7816Tag`, **`NFCMiFareTag`**
> — https://developer.apple.com/documentation/corenfc/nfcndeftag

∴ a tag obtained from an `NFCTagReaderSession` **is** an `NFCNDEFTag`, and the four required
members of that protocol are available on it:

| member | use here |
|---|---|
| `queryNDEFStatus(completionHandler: (NFCNDEFStatus, Int, Error?) -> Void)` | **the capacity precheck.** `Int` = capacity in bytes |
| `readNDEF(completionHandler:)` | read-before-write, and read-back-after-write |
| `writeNDEF(_:completionHandler:)` | "Saves an NDEF message to a writable tag" |
| `writeLock(completionHandler:)` | **must never be called** — see §2.9 |

`NFCNDEFStatus` is `notSupported` / `readOnly` / `readWrite`
(https://developer.apple.com/documentation/corenfc/nfcndefstatus).

Apple ships a sample for precisely this: **"Creating NFC Tags from Your iPhone" — "Save data
to tags, and interact with them using native tag protocols"**, `iOS 14.0+`
(https://developer.apple.com/documentation/corenfc/creating-nfc-tags-from-your-iphone).

**Verdict: writing NDEF from an App Store iOS app is permitted in 2026, using
`NFCTagReaderSession` with `com.apple.developer.nfc.readersession.formats = ["TAG"]`.**
`NFCNDEFReaderSession` is not the way — its only documented entitlement is the same key, whose
only documented value is `TAG`.

**One API note for whoever implements it:** `NFCTagReaderSession.init(pollingOption:delegate:
queue:)` is marked **Deprecated** on that page. The current initialiser is
`init(configuration: NFCTagReaderSession.Configuration, delegate:queue:)`. Target the
configuration form or the first build warns and the second one breaks.

## 2.2 The rejection risk, stated plainly

**Say it in one line: re-adding `com.apple.developer.nfc.readersession.formats` to this app is
re-touching the exact key that failed App Store submission with error 90778.**

What is different now, and what is not:

| | |
|---|---|
| ✓ different | the value is `["TAG"]`, not `["NDEF"]`. `TAG` is the one currently documented value |
| ✓ different | the session class is `NFCTagReaderSession`, which is what the error message asked for |
| ✗ **not** different | it is the same entitlement key, gated by the same "Near Field Communication Tag Reading" capability on the App ID, which must be enabled in the developer portal and re-issued into the provisioning profile |
| ✗ **not** different | Guideline 2.5.1 still applies. A timesheet app requesting NFC tag access is a question a reviewer may ask, and the honest answer — "the administrator programmes the door tags" — is fine, but it is a conversation |

**The consequence that matters more than the feature.** 90778 is an **upload validation**
failure, not a review rejection: it fires at Transporter/`altool` time, before a human sees
the build. That is good — it is cheap to discover. But this repo's history says the blast
radius is not the feature:

> `BACKLOG-TRIAGE.md`: "Seven commits of work are on nobody's phone… the cold-launch tap fix
> and the NSUserActivity handling… If the pilot stopped because taps were unreliable, the fix
> already exists and is not on the device that needs it."

A build that will not upload blocks **every** iOS fix riding in it. So:

> **Rule: the NFC entitlement change ships in a build of its own.** Never in the same archive
> as a clock-in fix, a German string fix, or anything a worker is waiting for. Validate that
> throwaway build to TestFlight, confirm it uploads, and only then let the feature ride
> normal builds.

Cost of that rule: one extra archive+upload cycle. Cost of breaking it: the situation the
triage report already describes, again.

## 2.3 Therefore: Android first

The lazy-senior read of the whole feature:

- Android NDEF writing needs **`android.permission.NFC`, already in the manifest**, and no
  store gatekeeper, no capability, no entitlement, no review conversation.
- The Android app already has `nfc/ScanActivity.kt` doing foreground reader-mode dispatch,
  already reads `Ndef` messages, and already converges everything through `TagLink`. Tag
  writing is that file plus `Ndef.writeNdefMessage()`.
- The tags get written **once**, by **one** person, in a **van**. This does not need to work
  on both platforms to be worth having.

∴ **ship Android tag writing first and completely. Treat the iOS entitlement as a separate,
isolated spike.** If the director only carries an iPhone, buy a cheap Android handset before
buying an App Store rejection — it costs less and it cannot block a clock-in fix.

⚠ **Not verified: Android NFC has never executed on real hardware in this project.**
`BACKLOG-TRIAGE.md` TASK-42 — every Android NFC test to date ran on an emulator, which has no
NFC radio. Tag *writing* on Android is blocked behind the same single unproven tap. That
ordering is not optional: TASK-42 first.

## 2.4 "Admin mode" — what it is, and how it is gated

**It is not a mode.** A mode is a flag on a device, and a flag on a device is one setting
screen away from a worker who is curious, or one handed-over phone away from a worker who is
not.

**It is a capability token, minted by the server, scoped to one location, valid once.**

```
web panel (admin session, decision-20)
  → building/zone page → [ Tag schreiben ]
  → POST /admin/tag-write-tokens {location_uuid}
  → panel renders a QR of  https://timesheets.exe.xyz/w?k=<token>
phone (any, no login needed, camera)
  → scans QR → App Link opens the app straight at the write screen
  → app GETs /tag-write/<token> → {location_uuid, name, url_to_write, expires_at}
  → writes → reads back → POSTs the result
```

Properties, each of which replaces something a "mode" would have needed:

| property | replaces |
|---|---|
| minted only by an authenticated **admin** web session | a PIN, a password prompt in the app |
| **single location**, named in the token | a location picker in the app, and every mis-target it enables |
| **single use**, consumed on successful write | "did I leave admin mode on?" |
| **~15 min TTL** | a logout button |
| server records who minted it and for what | an audit trail you would otherwise have to invent |

**A worker can never reach it** because a worker has no admin web session and therefore cannot
mint a token; and with no token the write screen has nothing to write and refuses to open. The
screen has **no entry point in the worker UI at all** — no menu item, no long-press, no
seven-taps-on-the-version-number. The only door is a URL that only an admin can create.

Reuses machinery that exists: `server/lib/enrolment.js` already generates and normalises
single-use, TTL'd, rate-limited codes with a written-out entropy argument, and `lib/auth.js`
already has the per-IP and global limiters. **No new npm dependency** (decision-16/23 budget
intact).

**One well-known change, and it is the risky kind.** The write link is on the same host and so
must be in the AASA `paths`, which today is `["/t*"]` (`ops/branding.json` → generated
`server/wellknown/apple-app-site-association`). Adding `/w*` widens what the app claims.
It is a generated, committed file (decision-24) so the change is `ops/branding.json` +
`node ops/gen-wellknown.mjs --write` + `server/wellknown/verify.sh`. **`/t*` must not be
touched in the same edit**, and the verify script must assert `/t*` is still present — that
string is what makes every tag on every wall work. Android needs the matching intent-filter
path and the same care.

`ponytail:` a QR on screen rather than an in-app admin login. CEILING: the director needs the
panel open on another screen to write a tag. UPGRADE PATH: an admin login inside the app, only
once someone has actually been annoyed by the laptop.

## 2.5 Before writing: will this tag hold it?

**Never open a write session without answering this first.** The HOIV tag is the proof that
"unlocked" and "writable with our URL" are different things: it is unlocked, it is NDEF, and
it physically cannot hold 64 bytes in 46.

Needed bytes are computed locally from the exact URL that will be written (§1.1) — not
guessed, not a constant, because the host is white-labelled (`ops/branding.json`) and a longer
operator host changes the number.

**Android**

```kotlin
val ndef = Ndef.get(tag)                    // null -> not NDEF; try NdefFormatable
ndef.isWritable                             // false -> refuse
ndef.maxSize                                // getMaxSize(): "maximum NDEF message size in bytes"
```
`Ndef.getMaxSize()` "Does not cause any RF activity and does not block."
`writeNdefMessage()` throws `FormatException`, `TagLostException`, `IOException`,
`SecurityException` and "must not be called from the main application thread"
(https://developer.android.com/reference/android/nfc/tech/Ndef).

If `Ndef.get()` is null, try `NdefFormatable` — a blank NTAG straight out of the bag is often
unformatted and will otherwise be reported as "not a tag we can use", which is wrong and will
generate a support call.

**iOS**

```swift
tag.queryNDEFStatus { status, capacity, error in   // capacity: Int, bytes
    guard status == .readWrite, capacity >= needed else { /* refuse, show both numbers */ }
}
```

**The refusal must show both numbers.** Not "tag too small" — *"Dieser Tag fasst 46 Bytes, die
Adresse braucht 64."* A number the director can repeat on the phone to a supplier is worth ten
sentences of apology.

## 2.6 When it does not fit — the branch that is actually a feature

Two options, offered on the refusal screen, both real:

**(a) Replace the tag.** The panel names the part: **NTAG213, 144 bytes NDEF, ~€0.20**. That
is the recommendation, and 144 bytes leaves headroom for a longer white-label host.

**(b) Adopt this tag by serial.** Record `(serial → location_uuid)` on the server. The app
already knows how to use such a mapping — `nfc/KnownTags.kt` — and this is **that file's own
stated upgrade path #1**, arriving as a product feature instead of a release:

> "1. Serve the mapping from the API (a `tag_serials` table beside `locations`, fetched with
>  the roster) so adoption becomes an admin action instead of a release."

So the capacity check does not dead-end. It routes to the operation that gets that wall
working today, and the one hardcoded adoption in the app becomes a row that can be deleted
without a build.

**The cost must be on that screen, in the director's words, before he confirms** — quoting the
same file:

> "A tag with no URL cannot wake a closed app… An adopted tag therefore ONLY works through the
> in-app Scan screen: the worker opens the app and presses Scan. The passive 'hold the phone
> to the wall with the app closed' flow… does not apply to these tags."

Adoption is a downgrade. Offering it silently would be selling one.

**Shortening the URL was considered and rejected.** `https://` is already the 1-byte
abbreviated prefix. base64url'ing the UUID (36 → 22 chars) gives 50 bytes — still over 46, and
it breaks decision-21's wording and both parsers. A short opaque id (`?l=` + 8 chars) gives 32
bytes and fits, but it invalidates every tag already written, adds a lookup column, and trades
an unguessable id for a guessable one — the exact property decision-21 exists to protect. **Do
not shrink the URL. Buy the right tag.** Revisit only if 46-byte tags become the norm rather
than one inherited case.

## 2.7 Verification: read it back through the tap parser

> An unverified write is a tag that fails on a wall — at 06:00, in a building, with nobody
> there who can fix it.

The check is not "did `writeNdefMessage` return without throwing". It is:

```
write  →  read NDEF back off the tag
       →  extract first URI record
       →  TagLink.locationId(uri)            ← the SAME function the tap path calls
       →  == expected uuid ?  ✓ done  :  ✗ FAILED, tag state unknown
```

Using the identical parser is the whole point. `TagLink` has non-obvious behaviour that a
bespoke comparison would not reproduce: it lowercases, it strips a trailing `/`, it rejects
userinfo-smuggled hosts (`https://ourhost@evil.example.com/t`), it escapes `+` before
percent-decoding so `?l=+<uuid>` is rejected on Android the same way iOS rejects it, and it
demands canonical 8-4-4-4-12 hex rather than Java's lenient `UUID.fromString`. Every one of
those is a way a byte-identical-looking write could still fail at the door.

Both parsers are already covered by ported checks (`NFCTimeSheets/checks/tag-link-check.swift`,
`android/checks/core-check.kt`), so the verification step inherits that test suite for free.

**Mutation test the verifier, or it is not a verifier.** This project has been bitten three
times by checks whose negative case could not fail. Required proof, in the task's DoD:

- write a **deliberately wrong** UUID → the read-back check must report FAILED. Prove it goes
  RED.
- stub the read-back to return `nil` → must report FAILED, not "probably fine".
- remove the tag mid-write (`TagLostException` / iOS session invalidation) → must report
  FAILED and must **not** record a success server-side.

## 2.8 Mis-writes: detection and undo

**Before the write** — read what is already there and branch:

| existing content | behaviour |
|---|---|
| empty / unformatted | write |
| our URL, **same** location | "already correct" — offer rewrite, no alarm |
| our URL, **different** location | ⚠ name the building/zone it currently points at and require an explicit confirm. This is the tag-swap mistake, and it is silent otherwise |
| a foreign NDEF message | ⚠ show what it is; confirm before overwriting someone else's tag |

Capture the previous message bytes before overwriting. That is the undo.

**Undo** = write the captured bytes back. Available while the app still holds them, i.e. while
the screen is open. It is not a general "restore" feature and must not pretend to be: once the
screen is gone, the fix for a wrong tag is *write the correct target*, which is the same
operation and needs a fresh token.

**Server-side record — `tag_writes`.** One insert per attempt:
`location_id, tag_serial, wrote_at, admin_user, previous_uri, result (ok|capacity|failed|
verify_failed), bytes_needed, bytes_capacity`.

Cheap, and it answers the question nobody can answer today: **which serial is on which wall,
and when did it last change.** With that table, a tag that stops working is diagnosable from a
desk. Without it, it is a site visit.

## 2.9 Never lock a tag

`NFCNDEFTag.writeLock()` (iOS) and `Ndef.makeReadOnly()` (Android) are **irreversible**.

decision-15 keeps tags unlocked on purpose — it is the migration insurance that makes the
`timesheets.exe.xyz` hostname a reversible choice rather than the one irreversible decision in
the architecture. Locking a tag would strand it on that hostname forever and turn a DNS
problem back into a site visit.

∴ **the write screen exposes no lock affordance at all**, and the two API calls must not appear
anywhere in the tree. A grep-based check in `android/checks` and `NFCTimeSheets/checks` is the
cheapest possible enforcement and belongs in the DoD.

---

## 3. Decision records proposed

Three, all **proposed**, all filed. None supersedes anything.

**decision-33 — Zones are `locations` rows with `parent_id`, depth capped at one.**
The tag URI, both parsers and `shifts.location_id` are unchanged; existing shifts mean "whole
building" and are labelled `Gebäude gesamt`, never null; a building-level tap stays a complete
clock-in and there is no zone picker at clock-in; money, contracts and geocoding stay at the
building by constraint; area is `area_dm2` integer. Evidence: `&z=<uuid>` costs 103 NDEF bytes
against 46 available on the deployed tag.

**decision-34 — m²/hour is a planning figure about places, never a rating of people.**
Per zone only; per-worker figures only within a single zone against that zone's own median;
suppressed below n = 5; excludes unresolved auto-closed shifts and segments beyond 3× the
zone median; zones without an area are absent, never zero.

**decision-35 — Tag writing is a server-minted, single-use, single-location token; Android
first; iOS behind an isolated entitlement spike.**
`["TAG"]` + `NFCTagReaderSession` is the only permitted iOS path and it ships in a build of its
own. Capacity is checked before every write and a refusal offers replacement (NTAG213) or
serial adoption with its cost stated. Every write is read back through the production
`TagLink` parser. Tags are never locked.

## 4. Backlog tasks

Filed via the CLI; see §5 for what each one is blocked on.

| id | task | effort | blocked on |
|---|---|---|---|
| **TASK-78** | migration 006: `parent_id`, `area_dm2`, `floor`, depth trigger, money/geocode constraints | low | — |
| **TASK-80** | server: zone CRUD + `building(x)` rollups + `auto_closed` only across buildings | med | TASK-78 |
| **TASK-82** | web: `Bereiche` section on building detail, `Gebäude gesamt` in shifts, de/en parity | med | TASK-80 |
| **TASK-84** | Flächenleistung report with every suppression rule from §1.8 | med | TASK-80 |
| **TASK-86** | server: tag-write tokens + `tag_serials` + `tag_writes` + AASA `/w*` | med | — |
| **TASK-87** | Android: admin tag-write screen — capacity precheck, write, read-back, undo | med | TASK-42 (one real tap), TASK-86 |
| **TASK-89** | iOS SPIKE: `["TAG"]` entitlement uploads? throwaway build, no feature | low | Apple portal capability |
| **TASK-91** | iOS: tag writing via `NFCTagReaderSession` | med | TASK-89, TASK-86 |

Effort is relative and reflects surface touched, not confidence.

## 5. What I could not settle

1. **Whether Apple will accept the `["TAG"]` entitlement on *this* App ID.** The documentation
   says the value is valid; documentation is not a submission. Only TASK 7 answers it, and
   that is why it exists as a throwaway build.
2. **Whether the director has an Android phone.** The Android-first recommendation collapses
   to "buy a €90 handset" if not, and that is still cheaper than a blocked iOS build — but it
   is his money and his call.
3. **Whether zone-level tracking is wanted at all, or only zone-level *area*.** If the owner
   only wants m² per building for pricing, Part 1 shrinks to two columns and no tags, no
   `auto_closed` change, no new report. **Ask before building any of §1.6.** This is the
   single biggest scope fork in the document.
4. **The n = 5 suppression threshold and the 3× outlier bound are invented.** They are the
   right *shape* — suppress small samples, exclude implausible segments — but the numbers have
   no data behind them because there are 8 shifts in production. Revisit once there are
   enough shifts to plot.
5. **Whether a missed zone tap is common.** The whole zone-segment model rests on workers
   tapping a second tag inside a building they are already clocked into. Nobody has ever done
   that. If they do not, zone data will be sparse and biased in a way §1.8 mitigates but does
   not fix.

---

*Written 2026-08-12. No product code changed. Production not contacted. Apple and Android
documentation fetched live and quoted verbatim with URLs; the NDEF byte figures are computed
by the script in §1.1, which reproduces `KnownTags.kt`'s "about 64" as exactly 64.*
