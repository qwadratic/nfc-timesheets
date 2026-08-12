---
id: decision-35
title: >-
  In-app tag writing is a server-minted single-use single-location token -
  Android first, iOS behind an isolated TAG-entitlement spike
date: '2026-08-12 05:47'
status: proposed
---
## Context

Tags are written today with NFC Tools, a third-party app, by hand. The owner wants it in our
app.

**What iOS permits now, checked against Apple's live documentation rather than memory.**
`com.apple.developer.nfc.readersession.formats` today documents exactly ONE possible value:

> `TAG` — "Allows read and write access to a tag using `NFCTagReaderSession`."
> https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats

`NDEF` is no longer a documented value. That corroborates commit `e4ac6e2`, which removed the
in-app scanner and the entitlement after App Store error 90778 ("NDEF is disallowed … TAG is
missing in the entitlement") building against the iOS 26 SDK.

Writing is nevertheless available on the `TAG` path. `NFCTagReaderSession` requires only the
entitlement plus a non-empty `NFCReaderUsageDescription`
(https://developer.apple.com/documentation/corenfc/nfctagreadersession). It hands back an
`NFCMiFareTag`, and `NFCNDEFTag`'s "Inherited By" list is exactly `NFCFeliCaTag`,
`NFCISO15693Tag`, `NFCISO7816Tag`, `NFCMiFareTag`
(https://developer.apple.com/documentation/corenfc/nfcndeftag) — so `queryNDEFStatus`,
`readNDEF`, `writeNDEF` and `writeLock` are all available on it. Apple ships a sample for this
exact job: "Creating NFC Tags from Your iPhone", iOS 14.0+
(https://developer.apple.com/documentation/corenfc/creating-nfc-tags-from-your-iphone).

**The risk, stated plainly.** It is the same entitlement key that failed submission, gated by
the same "Near Field Communication Tag Reading" capability on the App ID. 90778 is an upload
VALIDATION failure, so it fires before a human review — cheap to discover, but a build that
will not upload blocks every other iOS fix riding in it. `BACKLOG-TRIAGE.md` already records
that situation once: seven commits stranded, two of them clock-in reliability fixes.

**Android has no gatekeeper.** `android.permission.NFC` is already in the manifest,
`nfc/ScanActivity.kt` already does foreground reader-mode dispatch and already reads NDEF, and
`Ndef.writeNdefMessage()` needs nothing else.

**The capacity problem is real and already deployed.** The tag at HOIV Arsenalstraße 11 is a
Mifare Ultralight EV1 with 46 bytes of NDEF capacity. Our URL is exactly 64 NDEF bytes
(computed, `backlog/docs/ZONES-AND-TAG-WRITING.md` §1.1). It is unlocked and it still cannot
hold our URL.

## Decision

**1. "Admin mode" is not a mode. It is a capability token.**
A mode is a flag on a device, and a flag on a device is one setting screen away from a curious
worker, or one handed-over phone away from an uncurious one.

```
web panel (admin session, decision-20) -> POST /admin/tag-write-tokens {location_uuid}
   -> panel shows a QR of  https://<host>/w?k=<token>
   -> phone scans -> App Link opens the app at the write screen, for that ONE location
```

The token is minted only by an authenticated admin web session, is scoped to a **single
location**, is **single use**, has a **~15 min TTL**, and records who minted it and for what.
A worker cannot mint one, and with no token the write screen has nothing to write and refuses
to open. **The screen has no entry point in the worker UI at all** — no menu item, no
long-press, no seven-taps-on-the-version-number. Reuses `server/lib/enrolment.js` and the
existing rate limiters in `lib/auth.js`; **no new npm dependency** (decision-16, decision-23).

**2. Android ships first and completely; iOS is a separate, isolated spike.**
The iOS entitlement change ships in a build of its OWN — never in the same archive as a
clock-in fix, a German string fix, or anything a worker is waiting for. Validate that
throwaway build uploads to TestFlight, and only then let the feature ride normal builds.
Android tag writing is itself blocked behind TASK-42: NFC has never executed on real Android
hardware, only on emulators, which have no radio.

**3. Capacity is checked BEFORE every write, against the exact URL to be written.**
Bytes needed are computed locally, not constant — the host is white-labelled
(`ops/branding.json`) and a longer operator host changes the number.
Android: `Ndef.isWritable()` + `Ndef.getMaxSize()`; `Ndef.get()` null -> try `NdefFormatable`,
because a blank NTAG out of the bag is often unformatted. iOS: `queryNDEFStatus` -> require
`.readWrite` and `capacity >= needed`.
**A refusal shows BOTH numbers**: "Dieser Tag fasst 46 Bytes, die Adresse braucht 64."

**4. When it does not fit, the refusal offers two real options, not an apology.**
(a) Replace with an **NTAG213** (144 bytes, ~EUR 0.20), named on screen. (b) **Adopt the tag by
serial** — a `tag_serials` row, which is `nfc/KnownTags.kt`'s own stated upgrade path #1
arriving as a product feature instead of a release. Adoption's cost is shown before the
director confirms, in his words: an adopted tag has no URL, so it cannot wake a closed app and
only works through the in-app Scan screen. Offering that silently would be selling a downgrade.
**Shortening the URL is rejected**: base64url'ing the UUID still overshoots 46, and a short
opaque id fits but invalidates every written tag and trades an unguessable id for a guessable
one — the property decision-21 exists to protect.

**5. Every write is verified by reading back through the production `TagLink` parser.**
Not "did the write call return". The read-back URI goes through the same
`TagLink.locationId()` the tap path calls, and must return the expected UUID. That parser
lowercases, strips a trailing slash, rejects userinfo-smuggled hosts, escapes `+` before
percent-decoding, and demands canonical 8-4-4-4-12 hex — every one of which is a way a
byte-identical-looking write still fails at the door.
**The verifier is mutation-tested or it does not exist**: writing a deliberately wrong UUID, a
nil read-back, and a tag removed mid-write must each go RED and must not record a success.

**6. Mis-writes are detected before and after.**
Before: read what is there. Our URL for a different location, or a foreign NDEF message, both
require an explicit confirm naming what is being overwritten. The previous bytes are captured
— that is the undo, available while the screen is open. After: a `tag_writes` row per attempt
(`location_id, tag_serial, wrote_at, admin_user, previous_uri, result, bytes_needed,
bytes_capacity`).

**7. Tags are NEVER locked.** `writeLock()` (iOS) and `makeReadOnly()` (Android) are
irreversible and would strand a tag on `timesheets.exe.xyz` forever, destroying the migration
insurance decision-15 is built on. The write screen exposes no lock affordance, and a
grep-based check in `android/checks` and `NFCTimeSheets/checks` asserts neither call appears
in the tree.

## Consequences

**One AASA change, of the dangerous kind.** `apple.paths` is `["/t*"]` today. The write link
needs `/w*`. It goes through `ops/branding.json` + `node ops/gen-wellknown.mjs --write` +
`server/wellknown/verify.sh` (decision-24). `/t*` must not be touched in the same edit, and
`verify.sh` must assert `/t*` is still present — that string is what makes every tag on every
wall work. Android needs the matching intent-filter path with the same care.

**`tag_writes` answers a question nobody can answer today**: which serial is on which wall, and
when it last changed. With it, a dead tag is diagnosable from a desk. Without it, it is a site
visit.

**The Android-first recommendation collapses if the director carries only an iPhone.** Buying a
cheap Android handset is still cheaper than a blocked iOS build, but that is his money and his
call. Recorded so the trade-off is visible.

**Implementation note for iOS:** `NFCTagReaderSession.init(pollingOption:delegate:queue:)` is
marked Deprecated; target `init(configuration:delegate:queue:)`.

**What this does NOT do:** it does not reintroduce an in-app reader session on the clock-in
path. Background universal-link tap remains the only way a worker clocks in (`e4ac6e2`,
decision-5). Writing is admin-only and foreground-only.

Supersedes nothing. Constrained by decision-15 (never lock), decision-21 (UUID on the tag),
decision-24 (well-known files are generated and gated), decision-16/23 (dependency budget).
Depends on decision-20 for the admin session that mints the token.
