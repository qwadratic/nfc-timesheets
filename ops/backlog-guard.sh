#!/usr/bin/env bash
# ops/backlog-guard.sh - the checks behind the "record FIRST on the backlog branch" rule
# (AGENTS.md "Backlog branch", TASK-371). CI runs it (.github/workflows/backlog-gate.yml); a human
# or an agent can run the same thing before pushing.
#
#   ops/backlog-guard.sh branch [BACKLOG_REF]               origin/backlog holds ONLY backlog/**
#   ops/backlog-guard.sh mirror [REF] [BACKLOG_REF]         REF's backlog/ is a backlog-branch tree
#   ops/backlog-guard.sh ids    RANGE [BACKLOG_REF]         TASK-N / decision-N cited in RANGE exist
#   ops/backlog-guard.sh all    [REF] [RANGE]               the three, RANGE optional
#
# Defaults: BACKLOG_REF=origin/backlog, REF=HEAD. Exit 0 = ok, 1 = violation (message says which).
#
# WHY THESE THREE
#   branch  the backlog branch is the single writer of tasks/decisions; a code file landing there
#           would make "merge backlog into main" a code merge. The one exception is
#           ALLOWED_EXTRA (decision-84, TASK-372): the push-triggered gate workflow that runs this
#           very script, taken from main, on every push to the backlog branch.
#   mirror  main (or any work branch) may carry a backlog/ directory, but its content must be one
#           that EXISTED on the backlog branch. An edit made on a work branch is not a tree the
#           backlog branch ever had, so it is rejected: nothing reaches the regular backlog from
#           another branch. A mirror that merely LAGS the branch is fine.
#   ids     work may only cite records that already exist on the backlog branch ("no record, no
#           work"). A commit that really has no task may carry the line `Backlog-exempt: <why>`.
set -uo pipefail

BACKLOG_REF_DEFAULT="origin/backlog"
# The only path outside backlog/ the backlog branch may carry (decision-84).
ALLOWED_EXTRA=".github/workflows/backlog-gate-push.yml"
fail=0
say()  { printf '%s\n' "$*"; }
bad()  { printf 'BACKLOG-GUARD FAIL: %s\n' "$*" >&2; fail=1; }

# Resolve a ref to a commit SHA once and use the SHA everywhere: a branch called "backlog" and a
# directory called "backlog/" make the bare word ambiguous to git (a run from a work tree).
resolve() {
  local sha
  sha="$(git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null)" \
    || { bad "ref '$1' not found (git fetch origin backlog:refs/remotes/origin/backlog)"; return 1; }
  printf '%s' "$sha"
}

check_branch() {
  local name="${1:-$BACKLOG_REF_DEFAULT}" ref
  ref="$(resolve "$name")" || return
  local offenders
  # the tree at the tip ...
  offenders="$(git ls-tree -r --name-only -z "$ref" | tr '\0' '\n' | grep -v '^backlog/' | grep -vxF "$ALLOWED_EXTRA" || true)"
  if [ -n "$offenders" ]; then
    bad "$name holds paths outside backlog/ (tip):"; printf '  %s\n' $offenders >&2
  fi
  # ... and every commit in its history (a path added then removed still counts)
  local c paths
  for c in $(git rev-list "$ref" --); do
    paths="$(git diff-tree --root --no-commit-id --name-only -r -z "$c" | tr '\0' '\n' | grep -v '^backlog/' | grep -vxF "$ALLOWED_EXTRA" | grep -v '^$' || true)"
    if [ -n "$paths" ]; then
      bad "commit $(git rev-parse --short "$c") on $name touches paths outside backlog/:"; printf '  %s\n' $paths >&2
    fi
  done
  [ "$fail" = 0 ] && say "branch ok: $name holds only backlog/** ($(git rev-list --count "$ref" --) commits)"
}

check_mirror() {
  local rname="${1:-HEAD}" bname="${2:-$BACKLOG_REF_DEFAULT}" ref bref
  ref="$(resolve "$rname")" || return; bref="$(resolve "$bname")" || return
  local t
  t="$(git rev-parse --verify --quiet "$ref:backlog" || true)"
  if [ -z "$t" ]; then bad "$rname has no backlog/ directory"; return; fi
  local c
  for c in $(git rev-list "$bref" --); do
    if [ "$(git rev-parse --verify --quiet "$c:backlog" || true)" = "$t" ]; then
      say "mirror ok: backlog/ at $rname equals backlog/ at $bname~$(git rev-list --count "$c..$bref" --) ($(git rev-parse --short "$c"))"
      return
    fi
  done
  bad "backlog/ at $rname is not a tree the backlog branch ever had - it was edited outside it. Differences against the tip of $bname:"
  git diff --stat "$bref:backlog" "$ref:backlog" 2>/dev/null | tail -12 >&2
  say "  fix: move the change to the backlog branch (worktree ../cleaning-timesheets-backlog), push it, then 'git merge origin/backlog'." >&2
}

check_ids() {
  local range="$1" bname="${2:-$BACKLOG_REF_DEFAULT}" bref
  [ -n "$range" ] || { bad "ids needs a RANGE (base..head)"; return; }
  bref="$(resolve "$bname")" || return
  local listing; listing="$(git ls-tree -r --name-only "$bref" -- backlog | tr '[:upper:]' '[:lower:]')"
  local missing="" sha msg
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    msg="$(git log -1 --format=%B "$sha")"
    printf '%s' "$msg" | grep -qiE '^Backlog-exempt:' && continue
    # a pure merge of the backlog branch cites nothing
    ids="$(printf '%s' "$msg" | grep -oiE '\b(TASK-[0-9]+(\.[0-9]+)?|decision-[0-9]+)\b' | tr '[:upper:]' '[:lower:]' | sort -u)"
    local id
    for id in $ids; do
      case "$id" in
        task-*)      grep -qE "^backlog/(tasks|completed|archive/tasks)/${id} - " <<<"$listing" || missing="$missing\n  $(git rev-parse --short "$sha")  $id" ;;
        decision-*)  grep -qE "^backlog/decisions/${id}( - |-)" <<<"$listing"            || missing="$missing\n  $(git rev-parse --short "$sha")  $id" ;;
      esac
    done
  done < <(git rev-list --no-merges "$range" -- 2>/dev/null)
  if [ -n "$missing" ]; then
    bad "commits cite records that are not on $bname (record FIRST on the backlog branch, push it, then cite it):"
    printf "$missing\n" >&2
  else
    say "ids ok: every TASK-N / decision-N cited in $range exists on $bname"
  fi
}

mode="${1:-all}"; shift || true
case "$mode" in
  branch) check_branch "${1:-}" ;;
  mirror) check_mirror "${1:-}" "${2:-}" ;;
  ids)    check_ids "${1:-}" "${2:-}" ;;
  all)    check_branch; check_mirror "${1:-HEAD}"; [ -n "${2:-}" ] && check_ids "$2" ;;
  *) echo "usage: $0 branch|mirror|ids|all ..." >&2; exit 2 ;;
esac
exit "$fail"
