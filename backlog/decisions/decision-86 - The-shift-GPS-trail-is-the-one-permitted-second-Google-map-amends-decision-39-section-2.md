---
id: decision-86
title: >-
  The shift GPS trail is the one permitted second Google map, amends decision-39
  section 2
date: '2026-11-13 11:58'
status: accepted
---
## Context

decision-39 §2 removed the `/analytics/` map because "two maps in one admin are two things
that can disagree", and `web/scripts/check.mjs` enforces "exactly ONE screen constructs a
Google map". TASK-381 (shift evidence one click away) needs the admin to SEE a shift's GPS
samples: the owner rejected a latitude/longitude table as unusable and asked for an
interactive map of the points recorded every N minutes during a shift.

The disagreement risk decision-39 guards against is between two maps of BUILDINGS (pins,
states, numbers). A shift's GPS trail shows no buildings, no states and no numbers - only
one shift's own location samples - so it cannot contradict the buildings map.

## Decision

1. `web/components/ShiftEvidenceMap.tsx` (the GPS trail of ONE shift, opened from the
   shift evidence dialog) is the one permitted second Google map. Approved by the owner in
   conversation on 2026-11-13.
2. It never draws buildings, building pins, building states or any figure the buildings map
   shows. If it ever needs to, that is a new decision, not an extension of this one.
3. It reuses the existing loader and failure handling (`loadGoogleMaps`,
   `onMapsAuthFailure`, `failureOf`, `mapStyleFor`), builds the map once per mount, sets no
   `mapId`, and only loads when the evidence dialog is opened - never on page load.
4. Every other part of decision-39 stands. A third map anywhere still needs its own decision.

## Consequences

- `check.mjs`'s single-map gate names exactly two files: the buildings map and
  `ShiftEvidenceMap.tsx`; the no-`mapId` and build-once checks run on both.
- One extra Maps JavaScript map load per opened evidence dialog on the Maps bill (billing is
  per map load). Bounded by how often an admin opens evidence, not by traffic.
- With no key, a rejected key or no samples the map region is removed and a translated
  sentence shown; the photo stays visible.
