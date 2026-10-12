#!/usr/bin/env bash
# One-shot: give github.com/qwadratic/nfc-timesheets the Actions secrets the old
# proximata repo had, and switch Actions over so nothing deploys twice.
#
# WHY A SCRIPT AND NOT AN AGENT: GitHub never lets you read a secret back, so the values
# have to come from where they actually live (psst vault, the upload keystore, the Play
# console). Agent sessions are not allowed to write to a secret store; a human runs this.
# No value is in this file, none is printed, and every one goes in over stdin.
#
#   ./ops/qwadratic-secrets.sh              # do it
#   DRY_RUN=1 ./ops/qwadratic-secrets.sh    # say what it WOULD do, set nothing
#
# Prerequisites: gh authenticated as an account with admin on qwadratic/nfc-timesheets,
# psst vault of the main checkout (below), ~/keys/nfc-upload.jks, ssh access to exe.dev.
# Vault values are read via the `psst NAME -- cmd` injection form and never printed.
#
# NOT done here, because it needs a value only a human has:
#   PLAY_SERVICE_ACCOUNT_JSON  -> gh secret set PLAY_SERVICE_ACCOUNT_JSON --repo "$REPO" < sa.json
#                                 (Play Console -> Setup -> API access -> service account key)

set -euo pipefail

REPO="${REPO:-qwadratic/nfc-timesheets}"
OLD_REPO="${OLD_REPO:-proximata/nfc-timesheets}"
# psst is project-scoped: outside the project root it does not fail, it answers
# "Run: psst init" — so every vault read happens from here and is checked.
PSST_ROOT="${PSST_ROOT:-$HOME/Desktop/ai-automations/hoiv/cleaning-timesheets}"
KEYSTORE="${KEYSTORE:-$HOME/keys/nfc-upload.jks}"
KEY_ALIAS="${KEY_ALIAS:-upload}"
EXE_HOST="${EXE_HOST:-exe.dev}"
DRY_RUN="${DRY_RUN:-}"

say() { printf '%s\n' "$*" >&2; }
die() { say "ERROR: $*"; exit 1; }

command -v gh   >/dev/null || die "gh not installed"
command -v psst >/dev/null || die "psst not installed"
[ -r "$KEYSTORE" ] || die "keystore not found: $KEYSTORE"
[ -d "$PSST_ROOT" ] || die "PSST_ROOT is not a directory: $PSST_ROOT"

# put NAME  — value on stdin, never an argument, never echoed.
put() {
  local name="$1" value
  value="$(cat)"
  [ -n "$value" ] || die "$name: empty value"
  if [ -n "$DRY_RUN" ]; then say "  would set $name (${#value} bytes)"; return; fi
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" >/dev/null
  say "  set $name"
}

# vault_put VAULT_NAME TARGET — the vault value never leaves psst's injected environment:
# `psst NAME -- cmd` injects it and the gh call inside reads it from there. (Piping `psst get`
# would also work for a human, but psst redacts its OWN stdout, so the injection form is the
# one that cannot silently upload the literal text "[REDACTED]".)
# The command is a tiny helper FILE, not an inline `sh -c '...'`: psst does not preserve the
# quoting of an inline script (the first version of this uploaded nothing and said so).
helper="$(mktemp)"
cat > "$helper" <<'HELPER'
#!/bin/sh
v="$(printenv "$VAULT_NAME")"
[ -n "$v" ] || { echo "empty/missing $VAULT_NAME" >&2; exit 1; }
printf '%s' "$v" | gh secret set "$TARGET" --repo "$REPO" >/dev/null
HELPER
chmod 700 "$helper"
trap 'rm -f "$helper"; [ -z "${tmp:-}" ] || rm -rf "$tmp"' EXIT
vault_put() {
  local vault_name="$1" target="$2"
  if [ -n "$DRY_RUN" ]; then say "  would set $target from vault $vault_name"; return; fi
  (cd "$PSST_ROOT" && VAULT_NAME="$vault_name" TARGET="$target" REPO="$REPO" psst "$vault_name" -- "$helper") \
    || die "$target: vault read/upload failed ($vault_name)"
  say "  set $target"
}

say "== secrets for $REPO"
base64 < "$KEYSTORE" | tr -d '\n' | put TS_KEYSTORE_BASE64
printf '%s' "$KEY_ALIAS"                     | put TS_KEY_ALIAS
vault_put ANDROID_KEYSTORE_PASSWORD TS_KEYSTORE_PASSWORD
vault_put ANDROID_KEYSTORE_PASSWORD TS_KEY_PASSWORD
vault_put NEXT_PUBLIC_GOOGLE_MAPS_KEY WEB_MAPS_KEY
vault_put SENTRY_DSN_WEB WEB_SENTRY_DSN

say "== deploy key (CI-only ed25519, registered on the exe.dev ACCOUNT)"
tmp="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C "nfc-timesheets-ci@$REPO" -f "$tmp/k"
if [ -n "$DRY_RUN" ]; then
  say "  would register $(cut -d' ' -f1-2 "$tmp/k.pub" | cut -c1-40)… on $EXE_HOST and set SERVER_DEPLOY_SSH_KEY"
else
  ssh "$EXE_HOST" ssh-key add "$(cat "$tmp/k.pub")" >/dev/null
  put SERVER_DEPLOY_SSH_KEY < "$tmp/k"
fi

say "== Actions: old repo OFF first, new repo ON, so one push never deploys twice"
if [ -n "$DRY_RUN" ]; then
  say "  would disable Actions on $OLD_REPO and enable them on $REPO"
else
  gh api -X PUT "repos/$OLD_REPO/actions/permissions" -F enabled=false >/dev/null \
    || say "  could NOT disable Actions on $OLD_REPO (needs org admin) — do it in Settings -> Actions, then re-run"
  gh api -X PUT "repos/$REPO/actions/permissions" -F enabled=true -f allowed_actions=all >/dev/null
  say "  Actions enabled on $REPO"
fi

say
say "Still yours: PLAY_SERVICE_ACCOUNT_JSON (see header) and the Xcode Cloud repo repoint."
