#!/usr/bin/env bash
# ops/ios-rig/up.sh - bring the LOCAL VERIFICATION RIG up (TASK-365.22). Loopback only.
#
#   export RIG_HOME=<an absolute directory OUTSIDE the repo>
#   ops/ios-rig/up.sh            # database + API + TLS front + simulator clone + codes
#   ops/ios-rig/rig.sh build     # the app, built against 127.0.0.1:8444 (minutes, incremental)
#   ops/ios-rig/walk.sh p2-online-verified ...      (see README.md)
#   ops/ios-rig/down.sh          # everything above, gone
#
# WHAT COMES UP, in order, each step verified before the next:
#   1. a throwaway Postgres 18 cluster on 127.0.0.1:$RIG_PG_PORT (no unix socket), the server's
#      migrations applied, and an app role that is NOSUPERUSER NOBYPASSRLS (lib/db.js refuses
#      anything else, so the rig runs the REAL row-level security, not a bypass)
#   2. the seed (seed.sql): one company, two buildings, four zones, two workers, one operator
#   3. a throwaway CA + server certificate for 127.0.0.1
#   4. a CLONE of the iPhone 17 Pro simulator, booted, that trusts the CA (the original device
#      is never touched, and deleting the clone removes the certificate with it)
#   5. the real API (serve.mjs: server.js bound to 127.0.0.1) and the TLS front (front.mjs)
#   6. a fresh enrolment code per worker, written to $RIG_HOME/codes.env (0600)
set -u
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ -f "$STATE_ENV" ]; then
  die "the rig is already up ($STATE_ENV exists). Run ops/ios-rig/down.sh first."
fi
for tool in node openssl xcrun curl; do
  command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
done
for bin in initdb pg_ctl psql; do
  [ -x "$RIG_PG_BIN/$bin" ] || die "missing $RIG_PG_BIN/$bin (set RIG_PG_BIN)"
done
for p in "$RIG_API_PORT" "$RIG_FRONT_PORT" "$RIG_PG_PORT"; do
  port_busy "$p" && die "port $p is already in use"
done
[ -d "$REPO/server/node_modules/pg" ] || die "server dependencies are missing: (cd server && npm_config_manage_package_manager_versions=false pnpm install --frozen-lockfile --offline)"

umask 077
mkdir -p "$RIG_HOME" "$LOG_DIR" "$RUN_DIR" "$SHOT_DIR" "$TLS_DIR"
: > "$STATE_ENV"

# From here on, a failure takes the half-built rig down again.
fail() { log "FAILED at: $1 - tearing down"; "$HERE/down.sh" >/dev/null 2>&1; die "$1"; }

# ---- 1. throwaway Postgres ---------------------------------------------------------------------
SUPER_PW="$(openssl rand -hex 16)"
API_PW="$(openssl rand -hex 16)"
{ echo "SUPER_PW=$SUPER_PW"; echo "API_PW=$API_PW"; } > "$SECRETS_ENV"; chmod 600 "$SECRETS_ENV"
printf '%s' "$SUPER_PW" > "$RIG_HOME/.pwfile"
log "initdb ($PGDATA)"
with_timeout 120 initdb -D "$PGDATA" -U "$SUPER_ROLE" -E UTF8 --no-locale \
  --auth-local=scram-sha-256 --auth-host=scram-sha-256 --pwfile="$RIG_HOME/.pwfile" \
  >"$LOG_DIR/initdb.log" 2>&1 || fail "initdb (see $LOG_DIR/initdb.log)"
rm -f "$RIG_HOME/.pwfile"
cat >> "$PGDATA/postgresql.conf" <<EOF

# ---- ios-rig: loopback TCP only, no unix socket, no durability (it is a throwaway) ----
port = $RIG_PG_PORT
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
fsync = off
synchronous_commit = off
full_page_writes = off
max_connections = 40
shared_buffers = 32MB
timezone = 'UTC'
log_timezone = 'UTC'
EOF
with_timeout 90 pg_ctl -D "$PGDATA" -l "$LOG_DIR/pg.log" -w -t 60 start >/dev/null 2>&1 \
  || fail "postgres did not start (see $LOG_DIR/pg.log)"
log "postgres up on $HOST:$RIG_PG_PORT"

load_state
PGPASSWORD="$SUPER_PW" with_timeout 30 psql -h "$HOST" -p "$RIG_PG_PORT" -U "$SUPER_ROLE" -d postgres -X -q -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE $DB_NAME" \
  -c "CREATE ROLE $APP_ROLE LOGIN PASSWORD '$API_PW' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE" \
  || fail "create database / role"

log "migrations"
PGPASSWORD="$SUPER_PW" DATABASE_URL="postgres://$SUPER_ROLE@$HOST:$RIG_PG_PORT/$DB_NAME" \
  with_timeout 180 node "$REPO/server/db/migrate.js" >"$LOG_DIR/migrate.log" 2>&1 \
  || fail "migrations (see $LOG_DIR/migrate.log)"

rig_psql -c "GRANT USAGE ON SCHEMA public TO $APP_ROLE" \
         -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $APP_ROLE" \
         -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $APP_ROLE" >/dev/null \
  || fail "grants"
ROLE_CHECK="$(rig_sql "SELECT rolsuper::text || '/' || rolbypassrls::text FROM pg_roles WHERE rolname = '$APP_ROLE'")"
[ "$ROLE_CHECK" = "false/false" ] || fail "app role is not NOSUPERUSER NOBYPASSRLS ($ROLE_CHECK)"
log "app role $APP_ROLE: NOSUPERUSER NOBYPASSRLS ($ROLE_CHECK)"

# ---- 2. seed -------------------------------------------------------------------------------------
rig_psql -f "$HERE/seed.sql" >"$LOG_DIR/seed.log" 2>&1 || fail "seed (see $LOG_DIR/seed.log)"
state_set WORKER_A_ID "$(rig_sql "SELECT id FROM workers WHERE name='Anna Rig'")"
state_set WORKER_B_ID "$(rig_sql "SELECT id FROM workers WHERE name='Bernd Rig'")"
state_set TENANT_ID "$(rig_sql "SELECT id FROM tenants WHERE name='Rig Reinigung GmbH'")"
log "seeded (tenant $(rig_sql "SELECT id FROM tenants WHERE name='Rig Reinigung GmbH'"))"

# ---- 3. throwaway CA + server certificate ---------------------------------------------------------
(
  cd "$TLS_DIR" || exit 1
  openssl req -x509 -newkey rsa:2048 -sha256 -days 7 -nodes -keyout ca.key -out ca.pem \
    -subj "/CN=NFC TimeSheets RIG CA/O=local rig only" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null &&
  openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=127.0.0.1" 2>/dev/null &&
  printf 'subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\n' > ext.cnf &&
  openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 7 -sha256 -extfile ext.cnf 2>/dev/null
) || fail "certificates"
log "throwaway CA + server certificate for $HOST (7 days)"

# ---- 4. simulator clone ----------------------------------------------------------------------------
SIM_UDID="$(with_timeout 120 xcrun simctl clone "$RIG_SIM_SOURCE" "ts-ios-rig-$$" 2>"$LOG_DIR/simctl.log")" \
  || fail "simctl clone of $RIG_SIM_SOURCE (is it Shutdown? see $LOG_DIR/simctl.log)"
state_set SIM_UDID "$SIM_UDID"
with_timeout 120 xcrun simctl boot "$SIM_UDID" >>"$LOG_DIR/simctl.log" 2>&1 || fail "simctl boot $SIM_UDID"
with_timeout 180 xcrun simctl bootstatus "$SIM_UDID" -b >>"$LOG_DIR/simctl.log" 2>&1 || fail "simulator did not finish booting"
with_timeout 60 xcrun simctl keychain "$SIM_UDID" add-root-cert "$TLS_DIR/ca.pem" >>"$LOG_DIR/simctl.log" 2>&1 \
  || fail "simctl keychain add-root-cert"
log "simulator clone $SIM_UDID booted and trusting the rig CA"

# ---- 5. the API and the TLS front ------------------------------------------------------------------
api_start
front_start

# ---- 6. data + codes -------------------------------------------------------------------------------
"$HERE/rig.sh" reset-data >/dev/null || fail "reset-data"
issue_code A
issue_code B
log "codes written to $CODES_ENV (0600), 14 minute lifetime, single use: rig.sh new-code A|B reissues"
log "UP. rig home: $RIG_HOME"
log "next: ops/ios-rig/rig.sh build   then   ops/ios-rig/walk.sh list"
