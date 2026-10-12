#!/usr/bin/env bash
# ops/ios-rig/reskin-walk.sh - the PRESENTATION walks of the "Blue Hour" worker reskin
# (TASK-365.9 / .10 / .11). Where walk.sh drives BEHAVIOUR and asks Postgres and the wire what
# happened, this puts the worker's screens in front of the camera across the matrix the backlog
# asks for - appearance x language x text size - and leaves a PNG per step. It asserts nothing
# about the server; the structural assertions are the XCUITests' (WorkerRigReskinUITests).
#
#   ops/ios-rig/reskin-walk.sh                          the default matrix, every step
#   ops/ios-rig/reskin-walk.sh light-en-m dark-de-xxxl  these combinations only
#   STEPS="testB1IdleTabsMoreAndHistory" ops/ios-rig/reskin-walk.sh dark-en-m
#
# A combination is <appearance>-<language>-<size>: light|dark, en|de, m (the default "large"
# category) | xl | xxxl (accessibility-extra-extra-extra-large, the largest there is).
#
# It sets the CLONE's appearance and text size with `simctl ui` and puts both back on exit; it
# never touches any other simulator. Screenshots land in $RIG_HOME/shots, never in the repo.
#
# A step that needs the server flipped in the middle (a refused connection) stops at a named
# rendezvous and this driver flips it - the same protocol as walk.sh, a smaller vocabulary.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_state
[ -f "$STATE_ENV" ] || die "the rig is not up (run up.sh, then rig.sh build)"
RIG="$HERE/rig.sh"
SYNC="$RIG_HOME/sync"
CLASS=WorkerRigReskinUITests

DEFAULT_COMBOS="light-en-m dark-en-m light-de-m dark-de-xxxl light-en-xxxl"
DEFAULT_STEPS="testB1IdleTabsMoreAndHistory testB2IdleStartCard testB2ReceiptThenRecentCard testB3RunningField"
# Steps that need a server flip, or only one pair of combinations to prove: STEPS="testB2UnsentRowSaysWaiting
# testB3PendingAndDeliverySheet testB3OverdueNeutralField" reskin-walk.sh light-en-m dark-de-xxxl

size_category() {
  case "$1" in
    m) echo large ;;
    xl) echo extra-extra-large ;;
    xxxl) echo accessibility-extra-extra-extra-large ;;
    *) die "unknown size '$1' (m | xl | xxxl)" ;;
  esac
}

# ONE driver at a time: two of these share one simulator, one database and one sync directory, and
# each starts by uninstalling the app and resetting the data - the second would pull the first's
# phone out from under a running test.
LOCK="$RUN_DIR/reskin-walk.lock"
mkdir -p "$RUN_DIR"
mkdir "$LOCK" 2>/dev/null || die "another reskin walk is running (or died: remove $LOCK)"

restore_phone() {
  rmdir "$LOCK" 2>/dev/null
  xcrun simctl ui "$SIM_UDID" appearance light >/dev/null 2>&1
  xcrun simctl ui "$SIM_UDID" content_size large >/dev/null 2>&1
  [ -f "$RUN_DIR/front.pid" ] && pid_alive "$(cat "$RUN_DIR/front.pid")" || "$RIG" net-up >/dev/null 2>&1
  [ -f "$RUN_DIR/api.pid" ] && pid_alive "$(cat "$RUN_DIR/api.pid")" || "$RIG" server-start >/dev/null 2>&1
}
trap restore_phone EXIT

flip() {
  case "$1" in
    net-down) "$RIG" net-down >/dev/null ;;
    net-up) "$RIG" net-up >/dev/null ;;
    server-stop) "$RIG" server-stop >/dev/null ;;
    server-start) "$RIG" server-start >/dev/null ;;
    open-elsewhere) "$RIG" shift-open-elsewhere A A_VER '9 hours' >/dev/null ;;
    hold-close) "$RIG" fault set '[{"path":"/shifts/close","method":"POST","hold_ms":30000}]' >/dev/null ;;
    fault-clear) "$RIG" fault clear >/dev/null ;;
    new-code-A) "$RIG" new-code A >/dev/null; . "$CODES_ENV"; printf '%s' "$CODE_A" > "$SYNC/code_A.txt" ;;
    *) log "unknown rendezvous '$1' (ignored)" ;;
  esac
}

# run_step METHOD TAG LANG - one XCUITest, serving its rendezvous points until it ends.
run_step() {
  local method="$1" tag="$2" lang="$3" pid name
  rm -f "$SYNC"/*.ready "$SYNC"/*.go
  "$RIG" test "$CLASS/$method" "TS_RIG_TAG=$tag" "TS_RIG_LANG=$lang" > "$LOG_DIR/reskin-$tag-$method.out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    for r in "$SYNC"/*.ready; do
      [ -e "$r" ] || continue
      name="$(basename "$r" .ready)"
      [ -f "$SYNC/$name.go" ] && continue
      log "      rendezvous '$name'"
      flip "$name"
      touch "$SYNC/$name.go"
    done
    sleep 0.5
  done
  wait "$pid"; local rc=$?
  /usr/bin/grep -E "Test Case .*(passed|failed)|error:|XCTAssert" "$LOG_DIR/reskin-$tag-$method.out" | head -6 | sed 's/^/      /'
  return $rc
}

mkdir -p "$LOG_DIR" "$SYNC" "$SHOT_DIR"
COMBOS="${*:-$DEFAULT_COMBOS}"
STEPS="${STEPS:-$DEFAULT_STEPS}"
FAILS=0

sim_boot
"$RIG" server-start >/dev/null 2>&1 || true
"$RIG" net-up >/dev/null 2>&1 || true
"$RIG" sim-uninstall >/dev/null
"$RIG" reset-data >/dev/null 2>&1
"$RIG" new-code A >/dev/null
xcrun simctl ui "$SIM_UDID" appearance light >/dev/null 2>&1
xcrun simctl ui "$SIM_UDID" content_size large >/dev/null 2>&1
log "sign in once (English)"
run_step testSignInOnce signin en || { log "SIGN-IN FAILED: nothing else can run"; exit 1; }

for combo in $COMBOS; do
  appearance="${combo%%-*}"; rest="${combo#*-}"; lang="${rest%%-*}"; size="${rest#*-}"
  case "$appearance" in light|dark) ;; *) die "bad combination '$combo' (light|dark-en|de-m|xl|xxxl)" ;; esac
  xcrun simctl ui "$SIM_UDID" appearance "$appearance" >/dev/null 2>&1
  xcrun simctl ui "$SIM_UDID" content_size "$(size_category "$size")" >/dev/null 2>&1
  log "== $combo  (appearance $appearance, language $lang, text size $(size_category "$size"))"
  for step in $STEPS; do
    log "   $step"
    run_step "$step" "$combo" "$lang" || { FAILS=$((FAILS+1)); log "   FAIL $step ($combo)"; }
  done
done

log "reskin walk: $FAILS failing step(s); screenshots: $SHOT_DIR"
[ "$FAILS" -eq 0 ]
