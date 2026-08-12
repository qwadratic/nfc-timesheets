---
id: decision-33
title: >-
  Zones are locations rows with parent_id - depth capped at one, tag URI and
  existing shifts unchanged
date: '2026-08-12 05:47'
status: proposed
---
## Context

Today a location is a whole building with one tag at the entrance. The owner wants rooms,
floors and zones inside a building, each optionally with a square-metre area.

The tag is the constraint, not the schema. A tag carries `https://<host>/t?l=<uuid>`
(decision-5, decision-21) and is glued to a wall; changing its format means a site visit to
every building. Measured, with the script in `backlog/docs/ZONES-AND-TAG-WRITING.md` §1.1:

```
https://timesheets.exe.xyz/t?l=<uuid>              ->  64 NDEF bytes
https://timesheets.exe.xyz/t?l=<uuid>&z=<uuid>     -> 103 NDEF bytes   (+61 %)
Mifare Ultralight EV1 already deployed at HOIV     ->  46 bytes capacity
NTAG213                                            -> 144 bytes capacity
```

A second UUID parameter fits nothing at or below 128 bytes of NDEF capacity — the entire
cheap end of the tag market, including the one tag actually on a wall. It would also force a
coordinated change to two `TagLink` parsers, two check suites and decision-21's wording, for
no gain over reusing the parameter that already exists.

There are live shifts against a building that has no zones. Those rows must keep meaning
exactly what they meant.

## Decision

**A zone is a `locations` row with `parent_id` set. Not a new table, not a new id namespace.**

```sql
ALTER TABLE locations
  ADD COLUMN parent_id UUID REFERENCES locations(id),   -- NULL => building
  ADD COLUMN area_dm2  INTEGER CHECK (area_dm2 > 0),    -- square DECIMETRES, integer
  ADD COLUMN floor     TEXT;                            -- 'EG', '1. OG', 'Keller'
```

1. **Depth is capped at one**, enforced by trigger: a zone's parent must itself be a building.
   The cap is what buys a flat list UI instead of a tree widget, so it is a database
   constraint and not a convention.
2. **The tag URI does not change.** A zone tag is byte-for-byte the same shape as a building
   tag; only the UUID differs. Both `TagLink` implementations are unchanged — zero lines.
3. **`shifts.location_id` does not change.** It already references `locations(id)` and
   therefore already accepts a zone id the day the row exists. No shift row is migrated.
4. **A shift against a building is labelled "Gebäude gesamt"** — never "(keine Zone)", never
   an empty cell, never a warning icon. It is a first-class value, not a null. The sum of the
   zone buckets is NOT expected to equal the building bucket, and any report implying
   otherwise is wrong.
5. **A building-level tap stays a complete, valid clock-in.** There is no zone picker at
   clock-in, on either platform. The apps stay unaware that zones exist.
6. **Money, contracts and geocoding stay at the building**, by CHECK constraint and trigger:
   a zone may not carry `client_id`, `monthly_contract_cents`, `target_minutes_per_month`,
   `lat`/`lng`, and `location_contracts` refuses zone rows.
7. **`auto_closed` fires only across buildings.** Tapping a zone tag inside the building the
   worker is already clocked into closes the open shift with `auto_closed = FALSE` and opens
   a new one. Tapping a different building keeps `auto_closed = TRUE`, unchanged. The
   comparison is `COALESCE(parent_id, id)` and it is made **server-side** — the app does not
   know two UUIDs share a parent and must not be taught (decision-19: the server is
   authoritative for open shifts).
8. **Area is `area_dm2`, integer square decimetres** (1 m² = 100 dm²). Same reasoning as
   money-in-cents: the director types 12.5 for a toilet and it must survive a round trip and
   a division with no float near a number the business acts on. `NUMERIC` is exact in
   Postgres but `pg` returns it to JS as a string, and the first consumer that forgets to
   parse it produces a silent `NaN`.

## Consequences

**Nothing existing is invalidated.** `ADD COLUMN` gives every current row `parent_id = NULL`,
i.e. "building", which is what they already are. The 8 production shifts still resolve, still
total, still price, still pay. The tag at HOIV (serial `04:A1:A8:52:AE:5C:80`, adopted in
`KnownTags.kt` because 46 bytes cannot hold 64) is not touched.

**The failure mode this guards against is retroactive reinterpretation, not data loss.** Once
zones exist there is a standing temptation to render a building-level shift as "(keine Zone)",
which reads as a defect the director should chase. Point 4 exists to forbid that.

**A day in one building with three zones becomes three shift rows.** Payroll sums rows so pay
is unchanged, but the shifts list gets longer and must group by building + day or it reads as
noise.

**`ponytail:` adjacency list with a hard depth cap of 1.** CEILING: no floors-inside-wings, no
recursive rollup, no `ltree`, no closure table. UPGRADE PATH: the cap is a trigger and the
rollup is one `WITH RECURSIVE` — but do not build it speculatively, because the real cost of
depth >= 2 is a tree widget on the buildings screen.

**UI cost to a director who ignores zones: one table column reading `—`, and one collapsed
section with one button on the building detail page.** No sidebar entry: a zone is a property
of a building, never a destination.

**Open question that must be answered before point 7 is built:** whether the owner wants zone
*time* at all, or only zone *area* for pricing. If only area, this record shrinks to two
columns, no zone tags, no `auto_closed` change and no new report. See
`backlog/docs/ZONES-AND-TAG-WRITING.md` §5.3.

Supersedes nothing. Constrains decision-5 and decision-21 (both hold unchanged, which is the
point). Interacts with decision-6 and decision-30 (money stays per building) and decision-10
(the 8h auto-close predicate is untouched).
