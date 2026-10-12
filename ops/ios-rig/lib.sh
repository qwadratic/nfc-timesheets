#!/usr/bin/env bash
# ops/ios-rig/lib.sh - shared by up.sh, down.sh, rig.sh and walk.sh. SOURCED, never executed.
#
# THE RULES THIS FILE ENFORCES (TASK-365.22):
#   - LOOPBACK ONLY. Every address in play is 127.0.0.1. Nothing here names staging.
#   - Everything that is generated (cluster, CA, keys, codes, logs, screenshots, DerivedData)
#     lives under $RIG_HOME, which MUST be outside this repository. Nothing generated is ever
#     written inside the checkout.
#   - Nothing here can hang: every external command that can wait is wrapped in with_timeout.
#
# The rtk shell wrapper mangles bare grep/ls/git output (AGENTS.md), so anything parsed uses
# the absolute path.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

: "${RIG_HOME:=}"
if [ -z "$RIG_HOME" ]; then
  echo "ios-rig: RIG_HOME is not set. Export it to an ABSOLUTE directory OUTSIDE the repo," >&2
  echo "         e.g. export RIG_HOME=\"\$SCRATCHPAD/rig\" (the rig writes a database, keys and" >&2
  echo "         a CA there and deletes them in down.sh)." >&2
  exit 64
fi
case "$RIG_HOME" in
  /*) ;;
  *) echo "ios-rig: RIG_HOME must be absolute (got '$RIG_HOME')" >&2; exit 64 ;;
esac
case "$RIG_HOME/" in
  "$REPO"/*) echo "ios-rig: RIG_HOME must be OUTSIDE the repo ($REPO)" >&2; exit 64 ;;
esac

: "${RIG_API_PORT:=8082}"
: "${RIG_FRONT_PORT:=8444}"
: "${RIG_PG_PORT:=5433}"
: "${RIG_PG_BIN:=/opt/homebrew/bin}"
# 'iPhone 17 Pro' on this Mac. The rig CLONES it (never boots or edits the original), so a
# root certificate and an app container can never leak into a device somebody else uses.
: "${RIG_SIM_SOURCE:=C6F15E3C-C704-4367-AB99-BE4C63C2BED8}"

HOST=127.0.0.1
PGDATA="$RIG_HOME/pgdata"
TLS_DIR="$RIG_HOME/tls"
LOG_DIR="$RIG_HOME/logs"
RUN_DIR="$RIG_HOME/run"
SHOT_DIR="$RIG_HOME/shots"
DERIVED="$RIG_HOME/DerivedData"
STATE_ENV="$RIG_HOME/state.env"       # ids and the clone's udid: not secret
SECRETS_ENV="$RIG_HOME/secrets.env"   # db passwords: 0600, deleted by down.sh
CODES_ENV="$RIG_HOME/codes.env"       # CODE_A / CODE_B: 0600, deleted by down.sh
FRONT_LOG="$LOG_DIR/front.jsonl"      # one JSON line per request the app made
FAULTS="$RUN_DIR/faults.json"         # what front.mjs should break (rig.sh fault ...)
DB_NAME=rig
APP_ROLE=rig_api
SUPER_ROLE=rigsuper
BUNDLE_ID_DEFAULT="io.github.qwadratic.NFCTimeSheets"   # ops/branding.json is the source; see bundle_id

PATH="$RIG_PG_BIN:$PATH"
# macOS: "postmaster became multithreaded during startup" unless LC_ALL names a real locale.
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export PATH

log() { printf 'ios-rig: %s\n' "$*"; }
die() { printf 'ios-rig: ERROR: %s\n' "$*" >&2; exit 1; }

# with_timeout SECONDS cmd args... - no coreutils dependency, kills the whole job on expiry.
with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  # The watchdog's output is detached, or a $(...) around with_timeout would wait for its sleep.
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  /usr/bin/pkill -P "$wd" 2>/dev/null
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  return $rc
}

load_state() {
  # shellcheck disable=SC1090
  [ -f "$STATE_ENV" ] && . "$STATE_ENV"
  # shellcheck disable=SC1090
  [ -f "$SECRETS_ENV" ] && . "$SECRETS_ENV"
  return 0
}

state_set() { # state_set KEY VALUE  -> upsert in state.env
  local key="$1" value="$2"
  touch "$STATE_ENV"
  /usr/bin/grep -v "^${key}=" "$STATE_ENV" > "$STATE_ENV.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$value" >> "$STATE_ENV.tmp"
  mv "$STATE_ENV.tmp" "$STATE_ENV"
}

port_busy() { /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# The superuser connection (seeding, flipping state, asserting). TCP only: the cluster has no
# unix socket (the scratchpad path would not fit in sun_path anyway).
rig_psql() {
  PGPASSWORD="${SUPER_PW:?secrets.env not loaded}" with_timeout 30 psql \
    -h "$HOST" -p "$RIG_PG_PORT" -U "$SUPER_ROLE" -d "$DB_NAME" -X -q -t -A -v ON_ERROR_STOP=1 "$@"
}
# one scalar / one row of text
rig_sql() { rig_psql -c "$1"; }

pid_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

stop_pidfile() { # stop_pidfile FILE NAME
  local file="$1" name="$2" pid
  [ -f "$file" ] || return 0
  pid="$(cat "$file" 2>/dev/null)"
  if pid_alive "$pid"; then
    kill -TERM "$pid" 2>/dev/null
    local i=0
    while pid_alive "$pid" && [ $i -lt 40 ]; do sleep 0.25; i=$((i+1)); done
    pid_alive "$pid" && kill -KILL "$pid" 2>/dev/null
    log "stopped $name (pid $pid)"
  fi
  rm -f "$file"
}

# The one place the app's compiled-in key is read. The shipped app sends a CONSTANT
# (API.appKey, committed in cleartext on purpose, see API.swift), and the product may not be
# changed for the rig, so the loopback server has to accept exactly that constant. It is read
# from the source at start-up and handed to the server process by environment only.
app_key_from_source() {
  /usr/bin/grep -E 'static let appKey = "tsk_[0-9a-f]+"' "$REPO/NFCTimeSheets/NFCTimeSheets/API.swift" \
    | /usr/bin/sed -E 's/.*"(tsk_[0-9a-f]+)".*/\1/' | head -1
}

# ---- the seed's ids (seed.sql). Constants, so a test and a flip name a door the same way ------
BUILDING_A=a0000000-0000-4000-8000-0000000000a1
BUILDING_B=b0000000-0000-4000-8000-0000000000b1
ZONE_A_VER=a1000000-0000-4000-8000-000000000001     # Alpha . Stiege 1   verified
ZONE_A_UNV=a1000000-0000-4000-8000-000000000002     # Alpha . Keller      unverified
ZONE_A_DEACT=a1000000-0000-4000-8000-000000000003   # Alpha . Dachboden   verified, can be deactivated
ZONE_B_VER=b1000000-0000-4000-8000-000000000001     # Beta  . Haupteingang verified

# ---- processes -------------------------------------------------------------------------------
api_start() {
  load_state
  [ -n "${API_PW:-}" ] || die "secrets.env is missing (is the rig up?)"
  port_busy "$RIG_API_PORT" && die "port $RIG_API_PORT is busy"
  local key; key="$(app_key_from_source)"
  [ -n "$key" ] || die "could not read API.appKey from API.swift"
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  (
    cd "$REPO/server" || exit 1
    # Only what the server needs. No SENTRY_*, no TWILIO_*, no Google, no App Store Connect.
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
      DATABASE_URL="postgres://$APP_ROLE:$API_PW@$HOST:$RIG_PG_PORT/$DB_NAME" \
      APP_KEY="$key" PORT="$RIG_API_PORT" RIG_PUBLIC_DIR="$RUN_DIR/public" \
      nohup node "$HERE/serve.mjs" >> "$LOG_DIR/api.log" 2>&1 &
    echo $! > "$RUN_DIR/api.pid"
  )
  local i=0
  until /usr/bin/curl -s -o /dev/null --max-time 2 "http://$HOST:$RIG_API_PORT/auth/capabilities"; do
    i=$((i+1)); [ $i -gt 40 ] && { /usr/bin/tail -20 "$LOG_DIR/api.log" >&2; die "API did not come up"; }
    sleep 0.5
  done
  log "api up on $HOST:$RIG_API_PORT (pid $(cat "$RUN_DIR/api.pid"))"
}
api_stop() { stop_pidfile "$RUN_DIR/api.pid" "api"; }

front_start() {
  port_busy "$RIG_FRONT_PORT" && die "port $RIG_FRONT_PORT is busy"
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  [ -f "$FAULTS" ] || echo '[]' > "$FAULTS"
  nohup node "$HERE/front.mjs" --cert "$TLS_DIR" --port "$RIG_FRONT_PORT" \
    --upstream "$HOST:$RIG_API_PORT" --log "$FRONT_LOG" --faults "$FAULTS" \
    >> "$LOG_DIR/front.log" 2>&1 &
  echo $! > "$RUN_DIR/front.pid"
  local i=0
  until /usr/bin/curl -s -o /dev/null --max-time 2 --cacert "$TLS_DIR/ca.pem" "https://$HOST:$RIG_FRONT_PORT/__rig/ping"; do
    i=$((i+1)); [ $i -gt 40 ] && { /usr/bin/tail -20 "$LOG_DIR/front.log" >&2; die "TLS front did not come up"; }
    sleep 0.25
  done
  log "tls front up on $HOST:$RIG_FRONT_PORT (pid $(cat "$RUN_DIR/front.pid"))"
}
front_stop() { stop_pidfile "$RUN_DIR/front.pid" "tls front"; }

# ---- enrolment codes (decision-26/63: five digits, 15 minutes, single use, stored as SHA-256) --
# Written to codes.env (0600), NEVER to the repo and never to stdout.
issue_code() { # issue_code A|B
  local who="$1" name code
  case "$who" in A) name="Anna Rig" ;; B) name="Bernd Rig" ;; *) die "worker must be A or B" ;; esac
  code="$(printf '%05d' $(( $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 100000 )))"
  rig_sql "UPDATE workers SET enrolment_code_hash = encode(sha256(convert_to('$code','UTF8')),'hex'),
             enrolment_code_expires_at = now() + interval '14 minutes', enrolment_code_issued_at = now(),
             enrolment_code_redeemed_at = NULL WHERE name = '$name'" >/dev/null
  touch "$CODES_ENV"; chmod 600 "$CODES_ENV"
  /usr/bin/grep -v "^CODE_$who=" "$CODES_ENV" > "$CODES_ENV.tmp" 2>/dev/null || true
  printf 'CODE_%s=%s\n' "$who" "$code" >> "$CODES_ENV.tmp"
  mv "$CODES_ENV.tmp" "$CODES_ENV"; chmod 600 "$CODES_ENV"
}

# The bundle id of the app that was actually built (falls back to the branding default).
bundle_id() {
  local plist="$DERIVED/Build/Products/Debug-iphonesimulator/NFCTimeSheets.app/Info.plist"
  [ -f "$plist" ] && /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null && return 0
  echo "$BUNDLE_ID_DEFAULT"
}

# xcodebuild shuts the device down after a test run; every simctl call on the app container
# needs it booted. Idempotent (booting a booted device is an error we ignore).
sim_boot() {
  [ -n "${SIM_UDID:-}" ] || die "no simulator clone (is the rig up?)"
  with_timeout 120 xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1
  with_timeout 180 xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1
}
