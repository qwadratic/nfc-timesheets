# Re-recording the admin UX walkthrough

`docs/media/admin-ux-walkthrough.mp4` — 292 s, 1480×838, German, no audio track at all.
The admin panel and the same admin panel on a phone, side by side, against the seeded
`nfc_demo` database. Produced entirely by `demo/record-admin-ux.mjs`.

Written 2026-08-12. This is the second admin film, not a replacement for the first:
`admin-walkthrough.mp4` is a tour of the SCREENS and stays. This one is a tour of what the
UX pass changed, which is mostly not a screen.

---

## The exact commands

Run from the repo root. `«stack»` is the same one `backlog/docs/DEMO.md` §1 defines, and it
is reproduced here so this file is not a fragment:

```sh
# «stack»
psql -q -d nfc_demo -v ON_ERROR_STOP=1 -f demo/seed.sql
DATABASE_URL=postgres:///nfc_demo node demo/make-admin.mjs
cd web && NEXT_PUBLIC_API_BASE_URL="" NEXT_PUBLIC_DEFAULT_LOCALE=de pnpm build && cd ..
cd server && DATABASE_URL=postgres:///nfc_demo \
  APP_KEY="$(sed -n "s/^ts\.appKey=//p" android/branding.properties)" \
  PORT=8082 PUBLIC_DIR=../web/out node server.js &
cd ..
```

| Artefact | Command | Needs | Time |
|---|---|---|---|
| `admin-ux-walkthrough.mp4` + `admin-phone-{dashboard,shifts,payroll,workers}.png` + `admin-linkfilter.png` | «stack» then `node demo/record-admin-ux.mjs` | Chrome, ffmpeg | ~7 min |
| the same film, re-encoded without re-recording | `node demo/record-admin-ux.mjs --compose-only` | ffmpeg | ~2 min |
| a throwaway cut that skips the pacing gate and writes to `/tmp` | `node demo/record-admin-ux.mjs --compose-only --draft` | ffmpeg | ~2 min |

**Re-seed first, every time.** The run clocks somebody in, approves a material request and
mints a client-portal link, all of which persist. It refuses to start on a dirty database
rather than recording a different film — see *Pre-flight* below.

```sh
sh demo/check-guards.sh      # 24 checks, includes this recorder's two
node demo/check-captions.mjs # no frame carries two captions
node demo/check-record.mjs   # both frame cadences + the viewport override (needs «stack»)
```

`--compose-only` works because `stop()` writes the frame arrival times next to the frames
(`/tmp/ts-demo/frames-ux-{desktop,phone}/frames.json`) and the captions to
`/tmp/ts-demo/admin-ux-plan.json`. A caption-band or layout question therefore costs two
minutes of ffmpeg, not seven minutes of Chrome. **Pacing and dwell cannot be fixed this
way** — they are recorded, not composed.

---

## What is in it

28 beats, every one of them narrated in German, burned into the frames.

```
login → Übersicht (question line, triage, phone cards)
      → MOCKED NFC TAP → the shift appears in „Gerade im Einsatz"
      → cross-link carrying a filter → „Aus einem Link gefiltert" → „Filter entfernen"
      → ?worker=999          → all rows + „es fehlt nichts"
      → ?period=…&from=…     → default view + „ungültigen Wert"
      → progressive disclosure (the explanation, then the create form)
      → Materialanforderungen (a real POST: eingereicht → genehmigt)
      → Mitarbeiter → Objekte → Kunden → Produkte & Geräte → Vertragsverwaltung
      → Lohnabrechnung → „Diese Stunden nachrechnen" carries an ABSOLUTE period
      → Gewinn & Verlust → Objektauswertung
      → the client portal, opened with the link minted on camera
```

**All 11 sidebar screens plus the portal**, and the run fails if one is missed: the list is
read out of `web/lib/nav.ts`, not kept in anybody's head.

### The phone pane

Right-hand pane, 300 px wide, **a real 390×844 Chrome viewport**, on for the whole film. It
walks the same screens at the same moment as the desktop one, so decision-29 is shown on
every screen rather than asserted once.

⚠ `--window-size=390,844` **is not a 390 px viewport.** Chrome clamps a window to a platform
minimum and opened it at 500×757. The first cut's phone pane was therefore a 500 px layout
under a caption that said 390 — still the card layout (500 < the 767 px breakpoint), so
nothing looked wrong. `demo/cdp.mjs` now imposes the viewport with
`Emulation.setDeviceMetricsOverride` and reads `innerWidth` back, throwing if it disagrees.

### The mocked tap

`POST /auth/code` then `POST /shifts/open` — the two requests the app sends after a real tag
read, with the real app key and the real endpoints. Nothing is stubbed and nothing about the
server is swapped; **the only thing missing is the radio.**

It is labelled twice while it lasts: the caption says so, and a yellow
*„NFC-TAP SIMULIERT — kein Funk, kein Gerät"* line sits across the top bar for the whole
window, on a black box, `enable`d between the two timestamps the run measured.

---

## Pre-flight (HTTP, before Chrome opens)

Two conditions, both of which cost one second here and a seven-minute take at the end:

- **Selim Kaya must have no open shift.** The server is authoritative for open shifts
  (decision-19), so a leftover makes the tap a clock-*out* and the dashboard beat narrates a
  row that never appeared.
- **Wohnhausanlage Donaufeld must not already be shared.** A shared building offers
  *„Neuer Link"*, not *„Mit Petra Aigner teilen"*. This one was paid for the expensive way:
  a full run died at the last beat.

Both say `re-seed: psql -q -d nfc_demo -f demo/seed.sql`.

---

## The gates, and the mutation that proves each one can fail

A check whose negative case cannot fail is not a check. Every one below was made to go RED
before it was trusted, and the exact mutation is recorded so it can be repeated.

| Gate | Mutation | What it printed |
|---|---|---|
| every sidebar screen is visited | — (inherited from `record-admin.mjs`, same regex over `nav.ts`) | — |
| **the caption is on screen long enough to read** — `max(5 s, chars/12)` | dwell shortened in the plan | `TOO FAST 1.0s < 7.6s Rechts wird aus jeder Tabellenzeile…` → exit 1 |
| **the two panes are the same length** | truncated `frames-ux-phone/frames.txt` | `the two panes are 192.60s apart` |
| **the caption track is the length of the picture** | `plan.total += 20` | `the picture is 292.60s but the captions are laid out over 312.53s` |
| **the thing a caption names is really in the viewport** (`reveal`) | fixed pixel offsets, which is what it replaced | `"Schicht von Hand erfassen" shows 0px of 49px in the phone pane` |
| **the viewport is the size the label claims** | `--window-size` alone | `asked for a 390x844 viewport and got 500x757` |
| **the recorder refuses a non-loopback target** | loopback check → `if (false)` | 3 FAIL in `check-guards.sh` |
| **the last frame is repeated** so the concat demuxer honours its duration | deleted that `lines.push` | 2 FAIL in `check-record.mjs` |
| **the fixed cadence is really uniform** | every duration forced to `0.020` | `the timeline is the wall-clock window (0.42s vs 2.14s)` |
| no frame carries two captions | `demo/check-captions.mjs`, already in the tree | — |

⚠ One gate is **not** mutation-proven here: deleting the read-back inside `setViewport` did
not make `check-record.mjs` go red, because in that experiment the override happened to work
anyway. Its value is historical rather than hypothetical — it is what caught the 500×757
viewport in the first place — but the check as written would not catch a *silently ignored*
override, only a rejected one.

### Two of those were real defects, not hypotheticals

**The concat demuxer stretches short frames.** It will not honour a duration below its own
0.04 s default, so a burst of screencast frames 5 ms apart is silently lengthened. On a 292 s
capture that added 18 s — a *different* amount to each pane — and moved every caption off the
screen it described. `startRecording(...).stop({ fps })` now samples the capture onto the
output's own 10 fps grid, where every entry is 0.1 s and nothing is clamped. Both panes now
measure 292.60 s against a 292.53 s caption track.

**`if cmd; then fail` was a false pass on the loopback guard.** With the guard deleted,
`DEMO_BASE=https://timesheets.exe.xyz node demo/record-admin.mjs` still exits non-zero —
because it reaches the live host and is turned away by a 401. The check reported *ok* for a
run that had already left the machine. All five recorder checks in `check-guards.sh` now match
the refusal WORDING, like the database ones already did.

> During that mutation, `demo/record-admin.mjs` and `demo/record-admin-ux.mjs` each got as far
> as one `POST /admin/login` against **the live server**, with the published demo credentials,
> and were refused. No session was issued and nothing was written. It is recorded here because
> a thing that touched production should be written down even when it was refused.

---

## The part no script can do

The run ends by printing a path:

```
NOW LOOK AT /tmp/ts-demo/admin-ux-contact-sheet.png
```

28 frames, one from the **middle** of every caption, tiled 4×7. Read each caption against the
two panes beside it. This is the only check that has ever caught a caption pointing at the
wrong screen: an assertion that a string is in the DOM passes happily while the picture shows
something else, which is exactly how the „folded-away form" beat first came out as a shot of
the middle of the shift table.

---

## What is deliberately NOT in it

- **A device.** No simulator, no emulator, no handset. The right-hand pane is the ADMIN PANEL
  at phone width, which is what decision-29 is about. The worker apps have their own films:
  `both-devices.mp4`, `ios-journey.mp4`, `android-journey.mp4`.
- **A map.** `/analytics/` says, in German, that this build carries no Google Maps key, and
  the film shows that rather than a nicer build (blocker 2 in `V2-FEATURES.md`).
- **Audio.** `-an`, no track at all.
- **Anything outside the browser.** Headless Chrome has no window chrome, no tab strip, no
  desktop and no notifications. The Mac's screen is never captured.
- **Any real person.** Every worker, client, contact, address and price comes from
  `demo/seed.sql` and is invented.
