#!/usr/bin/env bash
# ops/ios-rig/walk.sh - the DRIVERS of the driven walks (TASK-365.2 .. .7, via TASK-365.22).
#
#   ops/ios-rig/walk.sh list
#   ops/ios-rig/walk.sh p2-online-verified [more walks...]
#   ops/ios-rig/walk.sh p2                      every walk whose name starts with p2
#
# A walk is: put the server and the phone in a known state, run ONE small XCUITest (what the
# PHONE shows), flip server state at the test's named rendezvous points, then ask the DATABASE
# and the WIRE what really happened. Every assertion prints PASS or FAIL with what was
# observed; nothing is ticked anywhere automatically. The summary at the end is what a human
# reads before ticking a backlog criterion, and the evidence (screenshots, wire log, result
# bundles) stays under $RIG_HOME until down.sh --purge.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_state
[ -f "$STATE_ENV" ] || die "the rig is not up (run up.sh, then rig.sh build)"
RIG="$HERE/rig.sh"
SYNC="$RIG_HOME/sync"
MARKS="$SYNC/marks.txt"
WALKLOG="$LOG_DIR/walks.log"
PASS=0; FAILS=0

say() { printf '%s\n' "$*" | tee -a "$WALKLOG"; }
pass() { PASS=$((PASS+1)); say "  PASS  $CURRENT: $*"; }
fail() { FAILS=$((FAILS+1)); say "  FAIL  $CURRENT: $*"; }
check_eq() { # check_eq "what" expected actual
  if [ "$2" = "$3" ]; then pass "$1 (= $3)"; else fail "$1: expected '$2', got '$3'"; fi
}
check_ge() { if [ "$3" -ge "$2" ] 2>/dev/null; then pass "$1 (= $3, >= $2)"; else fail "$1: expected >= $2, got '$3'"; fi; }
sql() { rig_sql "$1"; }
wire() { node "$HERE/wire.mjs" --log "$FRONT_LOG" "$@"; }
wire_marks() { node "$HERE/wire.mjs" --log "$FRONT_LOG" --marks "$MARKS" "$@"; }

# ---- fixture ------------------------------------------------------------------------------
# A phone that has never run the app, a server with no shifts and no sessions, the seed's
# zones, no faults, fresh single-use codes for A and B.
fresh_phone() {
  "$RIG" server-start >/dev/null 2>&1 || true
  "$RIG" net-up >/dev/null 2>&1 || true
  "$RIG" sim-uninstall >/dev/null
  "$RIG" reset-data >/dev/null 2>&1
  "$RIG" new-code A >/dev/null
  "$RIG" new-code B >/dev/null
  rm -rf "$SYNC"; mkdir -p "$SYNC"
}
# Servers are restored whatever a walk did to them.
restore_servers() {
  [ -f "$RUN_DIR/api.pid" ] && pid_alive "$(cat "$RUN_DIR/api.pid")" || "$RIG" server-start >/dev/null 2>&1
  [ -f "$RUN_DIR/front.pid" ] && pid_alive "$(cat "$RUN_DIR/front.pid")" || "$RIG" net-up >/dev/null 2>&1
  echo '[]' > "$FAULTS"
}

# ---- running a test, with driver flips at its rendezvous points ----------------------------
TEST_PID=""
start_test() { # start_test Class/method [VAR=VALUE ...]
  rm -f "$SYNC"/*.ready "$SYNC"/*.go
  : > "$MARKS"
  TEST_NAME="$1"; shift
  "$RIG" test "$TEST_NAME" "$@" > "$LOG_DIR/walk-$CURRENT.out" 2>&1 &
  TEST_PID=$!
}
await_ready() { # await_ready NAME [seconds]
  local name="$1" limit="${2:-240}" i=0
  while [ ! -f "$SYNC/$name.ready" ]; do
    kill -0 "$TEST_PID" 2>/dev/null || { fail "the test ended before reaching rendezvous '$name'"; return 1; }
    sleep 0.5; i=$((i+1)); [ $i -gt $((limit*2)) ] && { fail "rendezvous '$name' not reached in ${limit}s"; return 1; }
  done
  say "        rendezvous '$name' reached"
}
go() { touch "$SYNC/$1.go"; }
finish_test() {
  wait "$TEST_PID"; TEST_RC=$?
  /usr/bin/grep -E "Test Case .*(passed|failed)|error:|XCTAssert|TEST EXECUTE" "$LOG_DIR/walk-$CURRENT.out" | head -8 | while read -r l; do say "        $l"; done
  if [ "$TEST_RC" -eq 0 ]; then pass "XCUITest ${TEST_NAME##*/} (phone-side assertions)"; else fail "XCUITest ${TEST_NAME##*/} failed (rc $TEST_RC): see $LOG_DIR/walk-$CURRENT.out"; fi
  TEST_PID=""
}
# run_test Class/method   (no rendezvous)
run_test() { start_test "$@"; finish_test; }

# A rendezvous NAME is also the flip the driver performs there (the test names the state it
# needs; this is the whole vocabulary). A walk may define hook_<name_with_underscores> to
# assert something about the server BEFORE the test is released.
flip() {
  case "$1" in
    net-down) "$RIG" net-down >/dev/null ;;
    net-up) "$RIG" net-up >/dev/null ;;
    server-stop|server-stopped) "$RIG" server-stop >/dev/null ;;
    server-start|server-back) "$RIG" server-start >/dev/null ;;
    revoke-A) "$RIG" revoke-sessions A >/dev/null ;;
    revoke-B) "$RIG" revoke-sessions B >/dev/null ;;
    revoke-all) "$RIG" revoke-sessions all >/dev/null ;;
    zone-add) "$RIG" zone-add >/dev/null ;;
    zone-deactivated) "$RIG" zone A_DEACT inactive >/dev/null ;;
    open-elsewhere) "$RIG" shift-open-elsewhere A B_VER >/dev/null ;;
    sched-none) "$RIG" schedule-set none >/dev/null ;;
    sched-one) "$RIG" schedule-set one >/dev/null ;;
    sched-cross) "$RIG" schedule-set cross >/dev/null ;;
    sched-multi) "$RIG" schedule-set multi >/dev/null ;;
    fault-clear) "$RIG" fault clear >/dev/null ;;
    new-code-A|new-code-B)
      "$RIG" new-code "${1##*-}" >/dev/null
      # shellcheck disable=SC1090
      . "$CODES_ENV"
      if [ "$1" = new-code-A ]; then printf '%s' "$CODE_A" > "$SYNC/code_A.txt"; else printf '%s' "$CODE_B" > "$SYNC/code_B.txt"; fi ;;
    fault-session-b)
      # GET /auth/session answers "Bernd Rig" (after 4 s, so the cached identity is seen first)
      "$RIG" fault set "[{\"path\":\"/auth/session\",\"method\":\"GET\",\"status\":200,\"delay_ms\":4000,\"body\":{\"worker\":{\"id\":$WORKER_B_ID,\"name\":\"Bernd Rig\"}}}]" >/dev/null ;;
    *) fail "unknown rendezvous/flip '$1'" ;;
  esac
}
# drive Class/method name1 name2 ...  - start the test, serve each rendezvous in order, finish
drive() {
  local test="$1"; shift
  start_test "$test"
  local name hook
  for name in "$@"; do
    await_ready "$name" || break
    hook="hook_$(echo "$name" | tr '-' '_')"
    flip "$name"
    type "$hook" >/dev/null 2>&1 && "$hook"
    go "$name"
  done
  finish_test
}

# ---- the walks -----------------------------------------------------------------------------
UI_MS=WorkerRigManualStartUITests
UI_SI=WorkerRigSignInUITests
UI_DL=WorkerRigDeliveryUITests

walk_signin() {
  fresh_phone
  run_test $UI_SI/testWorkerSignsInThroughTheCodeFormAndReachesIdle
  check_eq "one worker session row for worker A" 1 "$(sql "SELECT count(*) FROM worker_sessions WHERE worker_id = $WORKER_A_ID")"
  check_eq "the code was redeemed (single use)" "true" "$(sql "SELECT (enrolment_code_hash IS NULL AND enrolment_code_redeemed_at IS NOT NULL)::text FROM workers WHERE id = $WORKER_A_ID")"
  check_eq "POST /auth/code answered 200" 200 "$(wire --path /auth/code --method POST field status | tail -1)"
}

walk_p2_empty_state() {
  fresh_phone
  "$RIG" fault set '[{"path":"/roster","status":503}]' >/dev/null
  run_test $UI_MS/testEmptyZoneListShowsTheRefreshSentenceAndAsksNothing
  check_eq "requests between the sheet opening and the check" 0 "$(wire_marks --from sheet-opening --to sheet-checked n)"
  check_ge "the roster really was refused on this phone's launch" 1 "$(wire --path /roster --since $MARK0 n)"
  check_eq "no shift row on the server" 0 "$(sql "SELECT count(*) FROM shifts")"
  echo '[]' > "$FAULTS"
}

walk_p2_picker() {
  fresh_phone
  run_test $UI_MS/testPickerRowsAreSortedNothingPreselectedAndTheDialogNamesTheZone
  check_eq "looking at the dialog starts nothing: no shift row" 0 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "and posts nothing: no POST /shifts/open" 0 "$(wire --since $MARK0 --method POST --path /shifts/open n)"
}

walk_p2_online_verified() {
  fresh_phone
  run_test $UI_MS/testOnlineStartOfAVerifiedZoneOpensAnAcknowledgedShift
  # decision-81 by design: the sheet asks the server FIRST (201), then handleTap writes the row
  # and the sync pass re-posts the SAME client_uuid (200 duplicate), which acknowledges it.
  check_eq "POST /shifts/open count: the ask, then the sync pass's re-post" 2 "$(wire --since $MARK0 --method POST --path /shifts/open n)"
  check_eq "statuses in order (201 new, 200 duplicate)" "201 200" "$(wire --since $MARK0 --method POST --path /shifts/open field status | tr '\n' ' ' | sed 's/ $//')"
  check_eq "both carried the same client_uuid" 1 "$(wire --since $MARK0 --method POST --path /shifts/open field body.client_uuid | sort -u | wc -l | tr -d ' ')"
  check_eq "it carried the ZONE uuid" "$ZONE_A_VER" "$(wire --since $MARK0 --method POST --path /shifts/open field body.location_uuid | head -1)"
  check_eq "with manual:true" "true" "$(wire --since $MARK0 --method POST --path /shifts/open field body.manual | head -1)"
  check_eq "and the server answered 201" 201 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "server row count" 1 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "shifts.manual_start" "t" "$(sql "SELECT manual_start FROM shifts")"
  check_eq "shifts.location_id = the BUILDING" "$BUILDING_A" "$(sql "SELECT location_id FROM shifts")"
  check_eq "shifts.start_zone_id = the zone" "$ZONE_A_VER" "$(sql "SELECT start_zone_id FROM shifts")"
  check_eq "shift belongs to worker A and is open" "$WORKER_A_ID|open" "$(sql "SELECT worker_id || '|' || CASE WHEN end_time IS NULL THEN 'open' ELSE 'closed' END FROM shifts")"
}

walk_p2_unverified() {
  fresh_phone
  run_test $UI_MS/testUnverifiedZoneIsRefusedInlineAndWritesNothing
  check_eq "POST /shifts/open answered 422" 422 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "the refusal named the ZONE uuid" "$ZONE_A_UNV" "$(wire --since $MARK0 --method POST --path /shifts/open field body.location_uuid | head -1)"
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "and only ONE request: the phone did not queue a retry" 1 "$(wire --since $MARK0 --method POST --path /shifts/open n)"
}

walk_p2_open_elsewhere() {
  fresh_phone
  start_test $UI_MS/testOpenShiftOnTheServerIsAnsweredInlineWithNoRow
  await_ready open-elsewhere && { "$RIG" shift-open-elsewhere A B_VER >/dev/null; go open-elsewhere; }
  finish_test
  check_eq "POST /shifts/open answered 409" 409 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "the server holds exactly the one shift from the other device" 1 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "and it is not a manual start" "false" "$(sql "SELECT manual_start::text FROM shifts")"
}

walk_p2_deactivated() {
  fresh_phone
  start_test $UI_MS/testZoneDeactivatedAfterCachingIsRefusedInlineWithNoRow
  await_ready zone-deactivated && { "$RIG" zone A_DEACT inactive >/dev/null; go zone-deactivated; }
  finish_test
  check_eq "POST /shifts/open answered 422" 422 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
  "$RIG" zone A_DEACT active >/dev/null
}

walk_p2_server_down() {
  fresh_phone
  start_test $UI_MS/testServerDownStartIsQueuedLocallyThenDeliveredOnPullToRefresh
  if await_ready server-stopped; then "$RIG" server-stop >/dev/null; go server-stopped; fi
  if await_ready server-back 120; then
    check_eq "while the server was down it held no shift row" 0 "$(sql "SELECT count(*) FROM shifts")"
    "$RIG" server-start >/dev/null; go server-back
  fi
  finish_test
  check_eq "exactly ONE server row after recovery" 1 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "the row is the manual start at the zone's building" "true|$BUILDING_A|$ZONE_A_VER" "$(sql "SELECT manual_start::text || '|' || location_id || '|' || start_zone_id FROM shifts")"
  local uuids; uuids="$(wire --since $MARK0 --method POST --path /shifts/open field body.client_uuid | sort -u | wc -l | tr -d ' ')"
  check_eq "every POST /shifts/open of the walk carried the SAME client_uuid" 1 "$uuids"
  check_eq "and it is the one the server row holds" "$(wire --since $MARK0 --method POST --path /shifts/open field body.client_uuid | sort -u | head -1)" "$(sql "SELECT client_uuid FROM shifts")"
  say "        POST /shifts/open statuses on the wire: $(wire --since $MARK0 --method POST --path /shifts/open field status | tr '\n' ' ')"
  say "        delivered by: $(/usr/bin/grep -o 'delivered-by-[a-z]*' "$MARKS" | head -1)"
  say "        requests after the pull: $(wire_marks --from pull n)  (GET /shifts/open after the pull: $(wire_marks --from pull --path /shifts/open --method GET n))"
}

walk_p2_mock() {
  fresh_phone
  start_test $UI_MS/testMockArmedManualStartWorksWithNoServer
  if await_ready net-down; then "$RIG" net-down >/dev/null; MARKN="$(wire count)"; go net-down; fi
  finish_test
  "$RIG" net-up >/dev/null
  check_eq "nothing reached the server (the front was down)" 0 "$(wire --since "${MARKN:-0}" n)"
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
}

walk_p2_stop() {
  fresh_phone
  run_test $UI_MS/testFinishWithoutATagClosesTheTapStartedShiftManually
  check_eq "server row: tap start (not manual), manual close, confirmed, not auto-closed" "false|true|true|false" \
    "$(sql "SELECT manual_start::text || '|' || manual_close::text || '|' || (corrected_at IS NOT NULL)::text || '|' || auto_closed::text FROM shifts")"
  check_eq "the close went over the wire with manual:true" "true" "$(wire --since $MARK0 --method POST --path /shifts/close field body.manual | head -1)"
  check_eq "the open went over the wire WITHOUT manual" "false" "$(wire --since $MARK0 --method POST --path /shifts/open field body.manual | head -1)"
}


# ---- P5 (TASK-365.6) ---------------------------------------------------------------------------
walk_p5_online() {
  fresh_phone
  run_test $UI_DL/testP5OnlineTapStartNeverFlashesNotConfirmed
  check_eq "one server row, open, a tap start (not manual) at the zone" "1|open|false|$ZONE_A_VER" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END || '|' || bool_or(manual_start)::text || '|' || min(start_zone_id::text) FROM shifts")"
  check_eq "POST /shifts/open answered 201" 201 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
}

walk_p5_unreachable() {
  fresh_phone
  hook_net_up() {
    check_eq "while unreachable the server held no shift row" 0 "$(sql "SELECT count(*) FROM shifts")"
    MARKU="$(wire count)"
  }
  drive $UI_DL/testP5UnreachableServerThenRecovery net-down net-up
  check_eq "after Refresh the server holds exactly one open row" "1|open" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END FROM shifts")"
  check_eq "the row is the tap start at the zone" "false|$ZONE_A_VER" "$(sql "SELECT manual_start::text || '|' || start_zone_id FROM shifts")"
  check_eq "its client_uuid is the one on the wire" "$(sql "SELECT client_uuid FROM shifts")" \
    "$(wire --since "${MARKU:-0}" --method POST --path /shifts/open field body.client_uuid | head -1)"
  say "        spoken label: $(cat "$SHOT_DIR/p5-06-spoken-label.txt" 2>/dev/null)"
  unset -f hook_net_up
}

walk_p5_refused() {
  fresh_phone
  run_test $UI_DL/testP5RefusedTapShowsTheRowsSentence
  check_eq "POST /shifts/open answered 422" 422 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
}

walk_p5_blocked() {
  fresh_phone
  drive $UI_DL/testP5BlockedRefusalShowsTheSentenceAndTheRedIcon zone-deactivated
  check_eq "POST /shifts/open answered 422" 422 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
  "$RIG" zone A_DEACT active >/dev/null
}

walk_p5_overdue() {
  fresh_phone
  "$RIG" shift-open-elsewhere A A_VER "9 hours" >/dev/null
  run_test $UI_DL/testP5OverdueShiftIsShownAsOverEightHours
}

# ---- P6 (TASK-365.7) ---------------------------------------------------------------------------
walk_p6_empty() {
  fresh_phone
  run_test $UI_DL/testP6EmptyQueueDrawsNoRowsAndNoSheet
}

walk_p6_waiting() {
  fresh_phone
  hook_net_up() {
    check_eq "the server holds no row while the shift is only on the phone" 0 "$(sql "SELECT count(*) FROM shifts")"
  }
  drive $UI_DL/testP6WaitingAttemptedThenRecovered net-down net-up
  check_eq "after recovery the server has both halves of the shift" "1|closed" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN bool_and(end_time IS NOT NULL) THEN 'closed' ELSE 'open' END FROM shifts")"
  check_eq "close came from a manual stop" "true" "$(sql "SELECT manual_close::text FROM shifts")"
  say "        sheet said: $(/usr/bin/grep -o 'sheet-says-[a-z-]*' "$MARKS" | head -1)"
  unset -f hook_net_up
}

walk_p6_blocked() {
  fresh_phone
  drive $UI_DL/testP6BlockedAndWaitingRowsAndTheRunningScreen zone-deactivated net-down net-up
  check_eq "server rows: the A_VER shift only (the refused start wrote none; the offline one never arrived)" 1 "$(sql "SELECT count(*) FROM shifts")"
  check_eq "the refusal was 422" 422 "$(wire --since $MARK0 --method POST --path /shifts/open field status | head -1)"
  "$RIG" zone A_DEACT active >/dev/null
}

walk_p6_signin() {
  fresh_phone
  drive $UI_DL/testP6SignInScreenShowsTheRowsAndTheSignInSentence net-down net-up
  check_eq "no server row" 0 "$(sql "SELECT count(*) FROM shifts")"
}

walk_p6_dynamic_type() {
  fresh_phone
  drive $UI_DL/testP6DynamicTypeTwoHundredPercentRowsWrapAndStayTappable net-down net-up
}

# ---- P3 (TASK-365.4): two workers on one phone ---------------------------------------------------
UI_SP=WorkerRigSharedPhoneUITests

walk_p3_signout() {
  fresh_phone
  run_test $UI_SP/testP3SignOutTearsDownTheBadgeAndKeepsTheShift
  check_eq "A's server shift is still open after sign-out" "1|open" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END FROM shifts WHERE worker_id = $WORKER_A_ID")"
  say "        badge reads (NOT asserted: the Simulator's icon never exposes a badge): $(/usr/bin/grep -o 'badge-[a-z-]*-[0-9]*' "$MARKS" | tr '\n' ' ')"
  check_eq "POST /auth/logout reached the server" 200 "$(wire --since $MARK0 --method POST --path /auth/logout field status | head -1)"
  check_eq "the worker session row was revoked by the logout" 0 "$(sql "SELECT count(*) FROM worker_sessions WHERE worker_id = $WORKER_A_ID")"
}

walk_p3_b_signin() {
  fresh_phone
  run_test $UI_SP/testP3BSignsInAndSeesNothingOfAs
  check_eq "A's shift is still open on the server" "1|open" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END FROM shifts WHERE worker_id = $WORKER_A_ID")"
  check_eq "B has no shift" 0 "$(sql "SELECT count(*) FROM shifts WHERE worker_id = $WORKER_B_ID")"
}

walk_p3_b_same_place() {
  fresh_phone
  run_test $UI_SP/testP3BTapsTheSamePlaceAsAsOpenRow
  check_eq "A's row: open, not auto-closed, unchanged" "open|false" \
    "$(sql "SELECT CASE WHEN end_time IS NULL THEN 'open' ELSE 'closed' END || '|' || auto_closed::text FROM shifts WHERE worker_id = $WORKER_A_ID")"
  check_eq "B has a NEW open row at the same zone" "1|open|$ZONE_A_VER" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END || '|' || min(start_zone_id::text) FROM shifts WHERE worker_id = $WORKER_B_ID")"
  check_eq "no POST /shifts/close went out under B's cookie" 0 "$(wire --since $MARK0 --method POST --path /shifts/close n)"
}

walk_p3_b_elsewhere() {
  fresh_phone
  run_test $UI_SP/testP3BTapsAnotherBuilding
  check_eq "A's row: open, not auto-closed, unchanged" "open|false" \
    "$(sql "SELECT CASE WHEN end_time IS NULL THEN 'open' ELSE 'closed' END || '|' || auto_closed::text FROM shifts WHERE worker_id = $WORKER_A_ID")"
  check_eq "B's row is at building B" "1|$BUILDING_B" "$(sql "SELECT count(*) || '|' || min(location_id::text) FROM shifts WHERE worker_id = $WORKER_B_ID")"
  check_eq "nothing was closed" 0 "$(wire --since $MARK0 --method POST --path /shifts/close n)"
}

walk_p3_a_returns() {
  fresh_phone
  drive $UI_SP/testP3AReturnsAndHerShiftIsThereToClose new-code-A
  check_eq "A's shift is closed on the server by A's own tap-out, not auto-closed" "1|closed|false" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN bool_and(end_time IS NOT NULL) THEN 'closed' ELSE 'open' END || '|' || bool_or(auto_closed)::text FROM shifts WHERE worker_id = $WORKER_A_ID")"
  check_eq "B never got a row" 0 "$(sql "SELECT count(*) FROM shifts WHERE worker_id = $WORKER_B_ID")"
}

walk_p3_session_rejected() {
  fresh_phone
  drive $UI_SP/testP3SessionRevokedMidShiftDropsToSignedOut revoke-A
  check_eq "A's shift is still open on the server" "1|open" \
    "$(sql "SELECT count(*) || '|' || CASE WHEN min(end_time::text) IS NULL THEN 'open' ELSE 'closed' END FROM shifts WHERE worker_id = $WORKER_A_ID")"
  say "        badge reads (NOT asserted): $(/usr/bin/grep -o 'badge-[a-z-]*-[0-9]*' "$MARKS" | tr '\n' ' ')"
}

walk_p3_replaced() {
  fresh_phone
  drive $UI_SP/testP3WorkerReplacedWithoutSignedOut fault-session-b
  say "        $(/usr/bin/grep -o 'cached-a-rows-[a-z-]*' "$MARKS" | head -1)"
  echo '[]' > "$FAULTS"
}

walk_p3_swipe_delete() {
  fresh_phone
  drive $UI_SP/testP3SwipeDeleteAsBOnlyRemovesBsRows new-code-A
  check_eq "swipe-delete is local only: both finished shifts are still on the server" 2 "$(sql "SELECT count(*) FROM shifts WHERE end_time IS NOT NULL")"
}

walk_p6_device_wide() {
  fresh_phone
  drive $UI_SP/testP6DeviceWideCountsAndWorkerScopedLists net-down net-up
  say "        $(/usr/bin/grep -o 'b-sees-[a-z-]*' "$MARKS" | head -1)"
  say "        server rows for A afterwards: $(sql "SELECT count(*) FROM shifts WHERE worker_id = $WORKER_A_ID")"
}

walk_p2_wire() { # no phone: a read over everything the P2 walks put on the wire
  CURRENT=p2-wire
  local total buildings
  total="$(wire --method POST --path /shifts/open n)"
  buildings="$( { wire --method POST --path /shifts/open field body.location_uuid | /usr/bin/grep -c -E "^($BUILDING_A|$BUILDING_B)$"; } 2>/dev/null)"
  check_ge "POST /shifts/open requests inspected in the whole wire log" 1 "$total"
  check_eq "of them carrying a BUILDING uuid" 0 "${buildings:-0}"
}

ALL_WALKS="signin p2-empty-state p2-picker p2-online-verified p2-unverified p2-open-elsewhere p2-deactivated p2-server-down p2-mock p2-stop p2-wire p5-online p5-unreachable p5-refused p5-blocked p5-overdue p6-empty p6-waiting p6-blocked p6-signin p6-dynamic-type p6-device-wide p3-signout p3-b-signin p3-b-same-place p3-b-elsewhere p3-a-returns p3-session-rejected p3-replaced p3-swipe-delete"

run_walk() {
  local name="$1" fn
  fn="walk_$(echo "$name" | tr '-' '_')"
  type "$fn" >/dev/null 2>&1 || die "no walk named '$name' (walk.sh list)"
  CURRENT="$name"
  MARK0="$(wire count)"
  say ""
  say "== $name  ($(date '+%H:%M:%S'))"
  "$fn"
  restore_servers
}

case "${1:-}" in
  ""|list|help) printf '%s\n' $ALL_WALKS; exit 0 ;;
esac
SELECTED=""
for arg in "$@"; do
  case "$arg" in
    all) SELECTED="$SELECTED $ALL_WALKS" ;;
    p1|p2|p3|p4|p5|p6) for w in $ALL_WALKS; do case "$w" in "$arg"-*) SELECTED="$SELECTED $w" ;; esac; done ;;
    *) SELECTED="$SELECTED $arg" ;;
  esac
done
mkdir -p "$LOG_DIR"
for w in $SELECTED; do run_walk "$w"; done
say ""
say "walk summary: $PASS passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
