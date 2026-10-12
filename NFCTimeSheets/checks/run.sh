#!/usr/bin/env bash
# Runs every NFCTimeSheets/checks/*.swift on a plain Mac. No Xcode project, no simulator,
# no device, no test framework — that is the point: everything covered here is logic that
# would otherwise only be discovered at a door, in the dark, with a tag in one hand.
#
#     cd NFCTimeSheets && ./checks/run.sh
#
# Each check is a top-level Swift script that gets `cat`-ed together with the production
# files it exercises and run by `swift`. Those files are Foundation-only ON PURPOSE — that
# constraint is why TagLink.swift, TapInbox.swift, MigrationCore.swift, Scrub.swift,
# Materials.swift and ShiftSignal.swift look the way they do.
#
# The recipe for each check is also written at the top of the check itself, so a single one
# can still be run by hand while working on it. This file exists so nobody has to remember
# six of them, and so "the checks pass" means the same thing to every person who says it.
#
# WHAT THIS CANNOT PROVE, and nothing on a Mac can: that a physical tag fires the universal
# link, that a Live Activity survives a reboot, that a locked screen is legible at 200%
# Dynamic Type. Those need a phone. See docs/LIVE-ACTIVITY-SETUP.md § "Verify on hardware".
set -uo pipefail

cd "$(dirname "$0")/.."     # NFCTimeSheets/

command -v swift >/dev/null 2>&1 || {
  echo "checks: swift not found. Install Xcode or the Command Line Tools." >&2
  exit 127
}

SRC=NFCTimeSheets
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failed=0

# name : production files it needs (in order), the check itself is checks/<name>.swift
run() {
  local name="$1"; shift
  local out="$TMP/$name.swift"
  # shellcheck disable=SC2068
  cat $@ "checks/$name.swift" > "$out"
  if swift "$out"; then :; else failed=1; fi
}

run tag-link-check      "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift"
run tap-inbox-check     "$SRC/TapInbox.swift"
run migration-check     "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/MigrationCore.swift"
run scrub-check         "$SRC/Scrub.swift"
run materials-check     "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/Materials.swift"
run shift-signal-check  "$SRC/ShiftSignal.swift"
# decision-57: OFF must stay OFF. See the check's header for why the default is the feature.
run flags-check         "$SRC/FeatureFlags.swift"
# decision-62: the cache-generation marker. Fires once per build change, never on a fresh
# install, never twice - see the check's header for the two silent failures it pins.
run app-update-check    "$SRC/AppUpdate.swift"
# decision-49: the byte encoder and the overwrite guard, safety-critical - wrong bytes
# ruin a physical card mounted to a building. See each check's own header for the exact
# TASK-220 regression it reproduces before going green.
run ndef-tag-check      "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/NdefTag.swift"
run write-guard-check   "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/NdefTag.swift" "$SRC/WriteGuard.swift"
# The write screen's step machine: exactly one panel, and a SECOND card in the same session
# starts clean. See the check's header for the three-panels-at-once bug it reproduces.
run write-tag-step-check "$SRC/WriteTagStep.swift"
# TASK-321/decision-63: five digits, no dash, no letter aliasing - and the same shape the
# SERVER mints, read out of server/lib/enrolment.js rather than copied. Android's
# core-check.kt has the twin of this; the two must never disagree.
run enrolment-code-check "$SRC/EnrolmentCode.swift"
# decision-43: which BUILDING a tapped zone belongs to - the names every list shows, the
# same-building rule on the tap path, and the building a material request carries. Also pins
# that a malformed or missing `zones` key in /roster can never cost the app its locations.
run zones-check         "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/Zones.swift"
# decision-81: "Start without a tag" picks a ZONE and asks the server first; a refusal writes no row.
run manual-start-check  "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/ManualStart.swift"
# TASK-365.4 (iOS P3): a shared phone belongs to whoever is signed in. The helper's behaviour is
# run for real (WorkerScope.swift is cat-ed in, with a struct standing in for Shift) AND the screens
# are read off disk as text, so no Shift read can skip the scope and sign-out tears the signals down.
run worker-scope-check  "$SRC/WorkerScope.swift"
# decision-76: a card that was written and reported but never made a zone is finished from
# Test a tag, and the scan that found it is also its test scan. Pins the ORDER (resolve, then
# verify with the id read off the card) and that Skip makes no verify call.
run finish-card-check   "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/FinishCard.swift"
# decision-80 / TASK-365.5 (iOS P4): the worker's PLANNED assignments are a picture, never an input. The wire
# (lenient per row, location_id never decoded), Europe/Vienna time with the device zone set to four others,
# the stale-answer / worker-change / cancel guard, the REAL store with an injected fetch, and the screens read
# as text: display only (not in refresh, the tap, sync or signals), no surface of their own, both languages,
# German = Android's verbatim. Reads checks' sources, the catalogue and ../android off disk.
run schedule-check      "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/WorkerScope.swift" "$SRC/LoadGuard.swift" "$SRC/ViennaTime.swift" "$SRC/ScheduleStore.swift"
# TASK-365.6 (iOS P5): "Not confirmed yet" is WORDS, never behaviour. The grace (an online tap is unacknowledged
# for one request, so the screen waits 2 s), the notice decision run for real, and the screens read as text: the
# notice is a SEPARATE view after the clock card (never inside it), no surface of its own, nothing hidden or
# disabled, the Live Activity not told, German = Android's verbatim. shift-signal-check pins the plan, the ladder
# and the re-arm after the push.
run pending-notice-check "$SRC/ShiftSignal.swift" "$SRC/PendingNotice.swift"
# TASK-365.7 / decision-82 (iOS P6): what the phone STILL HOLDS, said in words. The count run for real (an open shift
# whose OPEN landed is not pending, a refused close that reopened a row is not, a finish owed with a proof waits,
# blocked is never folded into waiting, and `state(of:)` equals syncPending's own filter over all 32 input
# combinations), the last attempt never invented or older than its row, exactly one waiting sentence, and the
# screens read as text: display only, device-wide through WorkerScope, no surface, nothing that promises automatic
# delivery (iOS has none) in either language, German = Android's verbatim except the one named adverb.
run pending-work-check  "$SRC/PendingWork.swift"
# TASK-365.8 / decision-83 (iOS P7): the finished-shift RECEIPT. When it is offered (0-120 s, captured once, kept until
# Continue, never re-offered, the server's millisecond echo of the finish is the same finish), what its delivery line says
# (the row's sentence / Sent / Sending... inside the grace / Saved on this phone) and the gate for the check, which is a
# separate question; and the screens read as text: a Section after the banner, the start Sections drawn only without it,
# Recent minus its row, inline, no surface of its own, fmtDur untouched, German = Android's verbatim.
run shift-receipt-check "$SRC/PendingWork.swift" "$SRC/ShiftReceipt.swift"
# decision-83: the one-shot ring-then-check plays ONLY after a clean server ACK. The gate run for real at fixed instants
# (pending / failed / blocked never; a late ACK, an adopted old shift, a second event, clock skew), the identity consumed
# BEFORE anything animates and also under Reduce Motion, clock-in and clock-out independent, Android's stage arithmetic to
# the constant, and the wiring as text (two call sites, nothing on the tap path knows it, never green, no strings).
run worker-motion-check "$SRC/ConfirmationMotion.swift"
# decision-83: "My hours", the server's last 60 days. The status order (no end first), the duration omitted for the running
# row, Vienna time with the device zone set to four others, the store run for real (stale / worker change / cancel / 401 /
# offline = status 0 only / a new entry is a new fetch) and the screens read as text: read-only, no total, no rate, no write,
# no cache, one fetch, no surface of its own, German = Android's verbatim.
run my-hours-check      "$SRC/Branding.swift" "$SRC/TagLink.swift" "$SRC/API.swift" "$SRC/WorkerScope.swift" "$SRC/LoadGuard.swift" "$SRC/ViennaTime.swift" "$SRC/MyHours.swift"
# TASK-365.22 D1: the server's answer (the OPEN's included) only ever RAISES a local close flag.
# Text-pinned: apply() is SwiftData-bound; the rig walks bug-offline-manual-stop / -switch drive it.
run sync-flags-check

# Reads Localizable.xcstrings off disk rather than being cat-ed together with source.
if swift checks/localisation-check.swift; then :; else failed=1; fi

# TASK-276: the operator gate must read the ts_operator cookie, never a UserDefaults flag
# that no sign-out clears. Reads the sources off disk - see the check's own header for why
# it cannot be cat-ed together with them.
if swift checks/operator-gate-check.swift; then :; else failed=1; fi

# decision-59: `sms_login` off must remove the SMS door from BOTH iOS sign-in paths, and
# the capability read must fail CLOSED. Reads the sources off disk, same reason as above.
if swift checks/sms-gate-check.swift; then :; else failed=1; fi

# decision-49: reads NFCTimeSheets.entitlements off disk — never writes it (owner-only file).
# Catches NDEF sneaking back into the array (App Store 90778) whether Xcode, a human or an
# agent put it there. Green with the capability off entirely.
if swift checks/entitlement-format-check.swift; then :; else failed=1; fi

if [ "$failed" -ne 0 ]; then
  echo "checks: FAILED" >&2
  exit 1
fi
echo "checks: OK"
