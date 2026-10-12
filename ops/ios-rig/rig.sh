#!/usr/bin/env bash
# ops/ios-rig/rig.sh - the small subcommands a driven walk uses to FLIP SERVER STATE between
# steps, read what the server and the wire saw, and run one XCUITest. TASK-365.22.
#
#   ops/ios-rig/rig.sh <subcommand> [args]        (RIG_HOME must be exported, see up.sh)
#
#   status                         what is running, the simulator clone, the seed ids
#   build                          xcodebuild build-for-testing, app pointed at 127.0.0.1:$RIG_FRONT_PORT
#   test CLASS/method [VAR=VALUE]  one XCUITest on the clone; VARs reach the test as TS_RIG_* env
#
#   new-code A|B                   fresh single-use enrolment code -> codes.env
#   reset-data                     no shifts, no requests, no sessions; zones/buildings/plan back to seed
#   zone KEY verified|unverified|inactive|active      KEY = A_VER A_UNV A_DEACT B_VER NEW
#   zone-add [NAME]                a NEW verified zone in building A (after the phone's roster); id -> ZONE_NEW
#   building KEY active|inactive   KEY = A B
#   schedule-set none|one|cross|multi     worker A's planned assignments (P4)
#   shift-open-elsewhere A|B ZONEKEY [AGO]  an open shift for that worker, made by "another device" (AGO e.g. '9 hours')
#   revoke-sessions A|B|all        delete worker session rows (the next request answers 401)
#
#   server-stop | server-start     kill / start the API (the front stays up: the app sees 502)
#   net-down | net-up              kill / start the TLS front (connection refused: the app sees status 0)
#   fault set '<json>' | fault clear      what the front breaks (see front.mjs)
#   wire-mark | wire-since MARK [--method M] [--path P] [list|n|field F]    the app's requests
#
#   sql "<SELECT ...>"             one statement, superuser, unaligned output
#   shifts                         every shift row, readable
#   sim-uninstall                  remove the app (and its data container) from the clone
#   sim-shot NAME                  PNG of the clone's screen -> $RIG_HOME/shots/NAME.png
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
load_state

cmd="${1:-}"; shift || true

need_up() { [ -f "$STATE_ENV" ] || die "the rig is not up (run up.sh)"; }

zone_id() { # zone_id KEY
  case "$1" in
    A_VER) echo "$ZONE_A_VER" ;; A_UNV) echo "$ZONE_A_UNV" ;; A_DEACT) echo "$ZONE_A_DEACT" ;;
    B_VER) echo "$ZONE_B_VER" ;; NEW) echo "${ZONE_NEW:?no NEW zone yet: rig.sh zone-add}" ;;
    *) die "unknown zone key '$1' (A_VER A_UNV A_DEACT B_VER NEW)" ;;
  esac
}
worker_id() { case "$1" in A) echo "$WORKER_A_ID" ;; B) echo "$WORKER_B_ID" ;; *) die "worker must be A or B" ;; esac; }
building_id() { case "$1" in A) echo "$BUILDING_A" ;; B) echo "$BUILDING_B" ;; *) die "building must be A or B" ;; esac; }

# tomorrow HH:MM / day-after HH:MM in Vienna wall-clock time, as timestamptz SQL
vienna_at() { # vienna_at DAYS_AHEAD 'H hours'
  echo "((date_trunc('day', now() AT TIME ZONE 'Europe/Vienna') + interval '$1 day $2 hours') AT TIME ZONE 'Europe/Vienna')"
}

case "$cmd" in
  status)
    need_up
    echo "RIG_HOME      $RIG_HOME"
    for n in api front; do
      pidf="$RUN_DIR/$n.pid"
      if [ -f "$pidf" ] && pid_alive "$(cat "$pidf")"; then echo "$n           up (pid $(cat "$pidf"))"; else echo "$n           DOWN"; fi
    done
    if [ -f "$PGDATA/postmaster.pid" ]; then echo "postgres      up (port $RIG_PG_PORT)"; else echo "postgres      DOWN"; fi
    echo "simulator     ${SIM_UDID:-none}"
    xcrun simctl list devices 2>/dev/null | /usr/bin/grep -F "${SIM_UDID:-__none__}"
    echo "worker ids    A=${WORKER_A_ID:-?} B=${WORKER_B_ID:-?}"
    echo "zones         A_VER=$ZONE_A_VER A_UNV=$ZONE_A_UNV A_DEACT=$ZONE_A_DEACT B_VER=$ZONE_B_VER ${ZONE_NEW:+NEW=$ZONE_NEW}"
    ;;

  sql) need_up; rig_sql "$1" ;;
  psql) need_up; rig_psql "$@" ;;

  new-code) need_up; issue_code "$1"; log "new code for worker $1 written to $CODES_ENV" ;;

  reset-data)
    need_up
    A="$WORKER_A_ID"; T="$TENANT_ID"
    rig_psql -c "TRUNCATE shifts, material_requests CASCADE" \
             -c "DELETE FROM worker_sessions" \
             -c "DELETE FROM planned_shifts" \
             -c "DELETE FROM zones WHERE id NOT IN ('$ZONE_A_VER','$ZONE_A_UNV','$ZONE_A_DEACT','$ZONE_B_VER')" \
             -c "UPDATE zones SET active = true, verified_at = now() WHERE id IN ('$ZONE_A_VER','$ZONE_A_DEACT','$ZONE_B_VER')" \
             -c "UPDATE zones SET active = true, verified_at = NULL, verified_by_operator_id = NULL WHERE id = '$ZONE_A_UNV'" \
             -c "UPDATE locations SET active = true" \
             -c "UPDATE workers SET active = true" >/dev/null
    state_set ZONE_NEW ""
    echo '[]' > "$FAULTS"
    "$0" schedule-set multi >/dev/null
    log "data reset (no shifts, no sessions, seed zones, plan = multi, no faults)"
    ;;

  zone)
    need_up
    id="$(zone_id "$1")"
    case "$2" in
      verified)   rig_sql "UPDATE zones SET verified_at = now() WHERE id = '$id'" ;;
      unverified) rig_sql "UPDATE zones SET verified_at = NULL, verified_by_operator_id = NULL WHERE id = '$id'" ;;
      inactive)   rig_sql "UPDATE zones SET active = false WHERE id = '$id'" ;;
      active)     rig_sql "UPDATE zones SET active = true WHERE id = '$id'" ;;
      *) die "state must be verified|unverified|inactive|active" ;;
    esac >/dev/null
    log "zone $1 ($id) -> $2"
    ;;

  zone-add)
    need_up
    name="${1:-Neue Stiege $(date +%H%M%S)}"
    id="$(rig_sql "INSERT INTO zones (tenant_id, location_id, name, verified_at, active)
                   VALUES ($TENANT_ID, '$BUILDING_A', '$name', now(), true) RETURNING id" | head -1)"
    state_set ZONE_NEW "$id"
    log "new verified zone '$name' in building A: $id"
    echo "$id"
    ;;

  building)
    need_up
    id="$(building_id "$1")"
    case "$2" in
      active) rig_sql "UPDATE locations SET active = true WHERE id = '$id'" ;;
      inactive) rig_sql "UPDATE locations SET active = false WHERE id = '$id'" ;;
      *) die "state must be active|inactive" ;;
    esac >/dev/null
    log "building $1 -> $2"
    ;;

  schedule-set)
    need_up
    shape="${1:-multi}"
    A="$WORKER_A_ID"; T="$TENANT_ID"
    plan() { # plan LOCATION STARTSQL ENDSQL NOTE
      echo "INSERT INTO planned_shifts (id, tenant_id, worker_id, location_id, starts_at, ends_at, note)
            VALUES (gen_random_uuid(), $T, $A, '$1', $2, $3, '$4');"
    }
    sql="DELETE FROM planned_shifts WHERE worker_id = $A;"
    case "$shape" in
      none) ;;
      one)   sql="$sql $(plan "$BUILDING_A" "$(vienna_at 1 8)" "$(vienna_at 1 12)" "")" ;;
      cross) sql="$sql $(plan "$BUILDING_A" "$(vienna_at 1 22)" "$(vienna_at 2 2)" "Fenster putzen")" ;;
      multi) sql="$sql $(plan "$BUILDING_A" "now() + interval '1 hour'" "now() + interval '3 hours'" "Schluessel beim Portier")
                       $(plan "$BUILDING_B" "$(vienna_at 1 8)" "$(vienna_at 1 12)" "")
                       $(plan "$BUILDING_A" "$(vienna_at 1 22)" "$(vienna_at 2 2)" "Fenster putzen")" ;;
      *) die "shape must be none|one|cross|multi" ;;
    esac
    rig_psql -c "$sql" >/dev/null
    log "worker A's plan: $shape ($(rig_sql "SELECT count(*) FROM planned_shifts WHERE worker_id = $A") rows)"
    ;;

  shift-open-elsewhere)
    need_up
    w="$(worker_id "$1")"; z="$(zone_id "$2")"; ago="${3:-5 minutes}"
    id="$(rig_sql "INSERT INTO shifts (tenant_id, worker_id, location_id, start_zone_id, start_time, client_uuid)
                   SELECT $TENANT_ID, $w, location_id, id, now() - interval '$ago', gen_random_uuid()::text
                     FROM zones WHERE id = '$z' RETURNING id" | head -1)"
    log "open shift $id for worker $1 at zone $2, started $ago ago (a second device)"
    ;;

  revoke-sessions)
    need_up
    case "$1" in
      all) rig_sql "DELETE FROM worker_sessions" >/dev/null ;;
      *) rig_sql "DELETE FROM worker_sessions WHERE worker_id = $(worker_id "$1")" >/dev/null ;;
    esac
    log "worker sessions revoked: $1"
    ;;

  server-stop) need_up; api_stop ;;
  server-start) need_up; api_start ;;
  net-down) need_up; front_stop ;;
  net-up) need_up; front_start ;;

  fault)
    need_up
    case "$1" in
      set) printf '%s' "$2" > "$FAULTS"; log "faults: $2" ;;
      clear) echo '[]' > "$FAULTS"; log "faults cleared" ;;
      *) die "fault set '<json>' | fault clear" ;;
    esac
    ;;

  wire-mark) need_up; node "$HERE/wire.mjs" --log "$FRONT_LOG" count ;;
  wire-since)
    need_up
    mark="$1"; shift
    # remaining args are wire.mjs options and a verb
    node "$HERE/wire.mjs" --log "$FRONT_LOG" --since "$mark" "$@"
    ;;

  shifts)
    need_up
    rig_psql -c "SELECT s.id, w.name AS worker, l.name AS building, z.name AS start_zone,
                        to_char(s.start_time AT TIME ZONE 'Europe/Vienna','DD HH24:MI:SS') AS start,
                        to_char(s.end_time AT TIME ZONE 'Europe/Vienna','DD HH24:MI:SS') AS stop,
                        s.auto_closed AS auto, s.manual_start AS m_start, s.manual_close AS m_close,
                        s.client_uuid
                   FROM shifts s JOIN workers w ON w.id = s.worker_id JOIN locations l ON l.id = s.location_id
                   LEFT JOIN zones z ON z.id = s.start_zone_id ORDER BY s.id" -P format=aligned
    ;;

  sim-uninstall)
    need_up
    sim_boot
    xcrun simctl terminate "$SIM_UDID" "$(bundle_id)" >/dev/null 2>&1
    with_timeout 60 xcrun simctl uninstall "$SIM_UDID" "$(bundle_id)" >/dev/null 2>&1
    log "app uninstalled from the clone (fresh container on the next run)"
    ;;

  sim-shot)
    need_up
    sim_boot
    mkdir -p "$SHOT_DIR"
    with_timeout 30 xcrun simctl io "$SIM_UDID" screenshot "$SHOT_DIR/$1.png" >/dev/null 2>&1
    echo "$SHOT_DIR/$1.png"
    ;;

  build)
    mkdir -p "$LOG_DIR" "$DERIVED"
    log "xcodebuild build-for-testing (log: $LOG_DIR/build.log)"
    ( cd "$REPO/NFCTimeSheets" && with_timeout 1800 xcodebuild build-for-testing \
        -project NFCTimeSheets.xcodeproj -scheme NFCTimeSheets \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
        TS_API_HOST="$HOST:$RIG_FRONT_PORT" TS_TAG_HOST="$HOST:$RIG_FRONT_PORT" CODE_SIGNING_ALLOWED=NO \
        > "$LOG_DIR/build.log" 2>&1 )
    rc=$?
    /usr/bin/grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)" "$LOG_DIR/build.log" | head -10
    app="$DERIVED/Build/Products/Debug-iphonesimulator/NFCTimeSheets.app/Info.plist"
    if [ -f "$app" ]; then
      echo "TSTagHost in the built Info.plist: $(/usr/libexec/PlistBuddy -c 'Print :TSTagHost' "$app")"
      echo "TSApiHost in the built Info.plist: $(/usr/libexec/PlistBuddy -c 'Print :TSApiHost' "$app" 2>/dev/null)"
    fi
    exit $rc
    ;;

  test)
    need_up
    sim_boot
    only="$1"; shift
    mkdir -p "$RIG_HOME/results" "$SHOT_DIR" "$LOG_DIR"
    stamp="$(date +%H%M%S)"
    result="$RIG_HOME/results/$(echo "$only" | tr '/' '_')-$stamp.xcresult"
    # Everything a test may know reaches it as TS_RIG_* via TEST_RUNNER_ (Xcode strips the
    # prefix). Codes come from codes.env, ids from this file: never from the test's source.
    # shellcheck disable=SC1090
    [ -f "$CODES_ENV" ] && . "$CODES_ENV"
    export TEST_RUNNER_TS_RIG_CODE_A="${CODE_A:-}" TEST_RUNNER_TS_RIG_CODE_B="${CODE_B:-}"
    export TEST_RUNNER_TS_RIG_SHOTS="$SHOT_DIR"
    mkdir -p "$RIG_HOME/sync"
    export TEST_RUNNER_TS_RIG_SYNC="$RIG_HOME/sync"
    export TEST_RUNNER_TS_RIG_ZONE_A_VER="$ZONE_A_VER" TEST_RUNNER_TS_RIG_ZONE_A_UNV="$ZONE_A_UNV"
    export TEST_RUNNER_TS_RIG_ZONE_A_DEACT="$ZONE_A_DEACT" TEST_RUNNER_TS_RIG_ZONE_B_VER="$ZONE_B_VER"
    export TEST_RUNNER_TS_RIG_ZONE_NEW="${ZONE_NEW:-}"
    export TEST_RUNNER_TS_RIG_BUILDING_A="$BUILDING_A" TEST_RUNNER_TS_RIG_BUILDING_B="$BUILDING_B"
    for kv in "$@"; do export "TEST_RUNNER_$kv"; done
    log "xcodebuild test-without-building -only-testing:NFCTimeSheetsUITests/$only"
    ( cd "$REPO/NFCTimeSheets" && with_timeout 900 xcodebuild test-without-building \
        -project NFCTimeSheets.xcodeproj -scheme NFCTimeSheets \
        -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DERIVED" \
        -only-testing:"NFCTimeSheetsUITests/$only" -resultBundlePath "$result" \
        -parallel-testing-enabled NO -disable-concurrent-destination-testing \
        TS_API_HOST="$HOST:$RIG_FRONT_PORT" TS_TAG_HOST="$HOST:$RIG_FRONT_PORT" CODE_SIGNING_ALLOWED=NO \
        > "$LOG_DIR/test-$stamp.log" 2>&1 )
    rc=$?
    /usr/bin/grep -E "Test Case .*(passed|failed)|error:|XCTAssert|TEST EXECUTE|Executed [0-9]+ test" "$LOG_DIR/test-$stamp.log" | head -40
    echo "log: $LOG_DIR/test-$stamp.log   result: $result"
    exit $rc
    ;;

  ""|help|-h|--help) /usr/bin/sed -n '2,32p' "$0" ;;
  *) die "unknown subcommand '$cmd' (rig.sh help)" ;;
esac
