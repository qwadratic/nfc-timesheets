#!/usr/bin/env bash
# ops/ios-rig/down.sh - take the rig down and leave nothing behind (TASK-365.22 criterion 1).
#
#   ops/ios-rig/down.sh            # processes, database, certificates, secrets, simulator clone
#   ops/ios-rig/down.sh --purge    # ... and DerivedData, the wire log and the screenshots too
#
# Safe to run twice and safe on a half-built rig: every step is "if it exists".
#
# What it does NOT touch: the original simulator the clone came from, any other simulator
# (an 'iPhone 17' somebody else booted stays booted), the repository, the user's keychain.
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1
load_state

front_stop
api_stop

if [ -d "$PGDATA" ]; then
  if [ -f "$PGDATA/postmaster.pid" ]; then
    with_timeout 60 pg_ctl -D "$PGDATA" -m fast -w -t 45 stop >/dev/null 2>&1 \
      || with_timeout 30 pg_ctl -D "$PGDATA" -m immediate stop >/dev/null 2>&1
    log "postgres stopped"
  fi
fi

if [ -n "${SIM_UDID:-}" ]; then
  # Only a device this rig cloned (its name says so): never an arbitrary UDID.
  name="$(xcrun simctl list devices 2>/dev/null | /usr/bin/grep "$SIM_UDID" | head -1)"
  case "$name" in
    *ts-ios-rig-*)
      with_timeout 60 xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1
      with_timeout 60 xcrun simctl delete "$SIM_UDID" >/dev/null 2>&1
      log "simulator clone $SIM_UDID deleted (its keychain, and the rig CA in it, went with it)"
      ;;
    "") log "simulator clone $SIM_UDID is already gone" ;;
    *) log "REFUSING to delete $SIM_UDID: it is not a ts-ios-rig clone ($name)" ;;
  esac
fi

# Keys, certificates, database, passwords, codes, pid files. Nothing in here is evidence.
rm -rf "$PGDATA" "$TLS_DIR" "$RUN_DIR" "$SECRETS_ENV" "$CODES_ENV" "$STATE_ENV" "$STATE_ENV.tmp" \
       "$CODES_ENV.tmp" "$RIG_HOME/.pwfile"
if [ "$PURGE" = 1 ]; then
  rm -rf "$DERIVED" "$LOG_DIR" "$SHOT_DIR" "$RIG_HOME/results"
  rmdir "$RIG_HOME" 2>/dev/null
  log "purged logs, screenshots and DerivedData"
fi

# Report what is still listening, so "nothing left" is a measurement and not a belief.
left=0
for p in "$RIG_API_PORT" "$RIG_FRONT_PORT" "$RIG_PG_PORT"; do
  if port_busy "$p"; then log "WARNING: port $p is still listening"; left=1; fi
done
[ "$left" = 0 ] && log "DOWN. ports $RIG_API_PORT / $RIG_FRONT_PORT / $RIG_PG_PORT are free"
exit "$left"
