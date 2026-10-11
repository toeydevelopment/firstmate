#!/usr/bin/env bash
# sf-epic-gate.sh - read-only merge gate for an epic pull request.
#
# Usage:
#   sf-epic-gate.sh [options] <owner/repo> <epic-pr-url-or-number>
#
# Options:
#   --parent <issue>   also require a closing line for every child issue of this parent issue
#   --config <path>    epic-delivery config (default: $SF_EPIC_DELIVERY_CONFIG, else
#                      $FM_HOME/config/epic-delivery.json); template in
#                      factory/config-templates/epic-delivery.json
#   --dispatch         start the E2E workflow on the epic branch when no run exists for the head SHA
#   --ledger           print the epic ledger (ticket, PR, status) instead of running the checks
#
# Checks, printed as a numbered PASS/FAIL list:
#   1. head branch matches epic/*
#   2. base branch is the repository default branch (otherwise GitHub does not auto-close issues)
#   3. the PR body has a Closes/Fixes/Resolves line for every issue closed by a PR merged into the epic branch
#   4. the PR body has such a line for every child issue of --parent (SKIP without --parent)
#   5. a successful run of the configured E2E workflow exists on the exact head SHA
#
# Exit codes: 0 every check passed, 1 at least one check failed, 2 usage or GitHub read error.
# The gate never merges or edits anything. The only write is the E2E workflow start under --dispatch.
# After a pass, firstmate merges with bin/fm-pr-merge.sh.
# The GitHub client is `gh` unless $SF_GH names another executable (the tests use a fixture-backed fake).
set -eu

GH=${SF_GH:-gh}
PARENT=""
CONFIG=""
DISPATCH=0
LEDGER=0
POS=()

die() { echo "sf-epic-gate: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --parent) [ "$#" -ge 2 ] || die "--parent needs an issue number"; PARENT=$2; shift 2 ;;
    --config) [ "$#" -ge 2 ] || die "--config needs a path"; CONFIG=$2; shift 2 ;;
    --dispatch) DISPATCH=1; shift ;;
    --ledger) LEDGER=1; shift ;;
    -h|--help) sed -n '2,/^set -eu/p' "$0" | sed '$d'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) POS+=("$1"); shift ;;
  esac
done
[ "${#POS[@]}" -eq 2 ] || die "usage: sf-epic-gate.sh [options] <owner/repo> <epic-pr-url-or-number>"
REPO=${POS[0]}
PR=${POS[1]}
case "$REPO" in */*) : ;; *) die "repo must be owner/repo" ;; esac
case "$PR" in
  https://github.com/*/pull/*)
    URL_REPO=${PR#https://github.com/}
    URL_REPO=${URL_REPO%%/pull/*}
    [ "$URL_REPO" = "$REPO" ] || die "PR URL repo $URL_REPO does not match $REPO"
    PR=${PR##*/pull/}
    PR=${PR%%[!0-9]*}
    ;;
esac
case "$PR" in ''|*[!0-9]*) die "epic PR must be a number or a pull request URL" ;; esac
case "$PARENT" in *[!0-9]*) die "--parent must be an issue number" ;; esac

# api <endpoint> [--list]: GET JSON; --list pages through an array endpoint and merges the pages.
api() {
  local out
  if [ "${2:-}" = "--list" ]; then
    out=$("$GH" api --paginate "$1") || die "GitHub read failed: $1"
    printf '%s' "$out" | jq -s 'add // []'
  else
    "$GH" api "$1" || die "GitHub read failed: $1"
  fi
}

# closing_refs: stdin text -> unique same-repo issue numbers named by a closing keyword.
closing_refs() {
  grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+' \
    | awk -v repo="$REPO" '{
        ref = $NF; sub(/^.*[ \t]/, "", ref)
        n = ref; sub(/^.*#/, "", n)
        r = ref; sub(/#.*$/, "", r)
        if (r == "" || tolower(r) == tolower(repo)) print n
      }' | sort -un
}

PR_JSON=$(api "repos/$REPO/pulls/$PR")
HEAD_REF=$(jq -r '.head.ref' <<<"$PR_JSON")
HEAD_SHA=$(jq -r '.head.sha' <<<"$PR_JSON")
BASE_REF=$(jq -r '.base.ref' <<<"$PR_JSON")
BODY=$(jq -r '.body // ""' <<<"$PR_JSON")
PR_STATE=$(jq -r 'if .merged_at then "merged" else .state end' <<<"$PR_JSON")
HEAD_ENC=$(jq -rn --arg s "$HEAD_REF" '$s|@uri')

TICKET_PRS=$(api "repos/$REPO/pulls?state=all&base=$HEAD_ENC&per_page=100" --list)

CHILDREN=""
if [ -n "$PARENT" ]; then
  CHILDREN=$(api "repos/$REPO/issues/$PARENT/sub_issues?per_page=100" --list \
    | jq -r --arg repo "$REPO" '.[] | select((.repository_url // "") | endswith("/repos/" + $repo)) | .number' | sort -un)
fi

if [ "$LEDGER" -eq 1 ]; then
  printf '%-10s %-8s %s\n' TICKET PR STATUS
  seen=" "
  while IFS=$'\t' read -r num status body; do
    [ -n "$num" ] || continue
    refs=$(printf '%s' "$body" | closing_refs || true)
    if [ -z "$refs" ]; then
      printf '%-10s %-8s %s\n' "-" "#$num" "$status"
    else
      for r in $refs; do
        printf '%-10s %-8s %s\n' "#$r" "#$num" "$status"
        seen="$seen$r "
      done
    fi
  done < <(jq -r '.[] | [.number, (if .merged_at then "merged" else .state end), (.body // "" | gsub("[\t\r\n]"; " "))] | @tsv' <<<"$TICKET_PRS")
  for c in $CHILDREN; do
    case "$seen" in *" $c "*) : ;; *) printf '%-10s %-8s %s\n' "#$c" "-" "no PR" ;; esac
  done
  printf '%-10s %-8s %s\n' "(epic)" "#$PR" "$PR_STATE"
  exit 0
fi

# Config is only needed for the E2E check.
[ -n "$CONFIG" ] || CONFIG=${SF_EPIC_DELIVERY_CONFIG:-}
[ -n "$CONFIG" ] || { [ -n "${FM_HOME:-}" ] && CONFIG=$FM_HOME/config/epic-delivery.json; }
[ -n "$CONFIG" ] && [ -f "$CONFIG" ] || die "epic-delivery config not found (use --config; template: factory/config-templates/epic-delivery.json)"
E2E_WF=$(jq -r --arg repo "$REPO" '.repos[$repo].e2eWorkflow // .default.e2eWorkflow // empty' "$CONFIG") || die "unreadable config: $CONFIG"

N=0
FAILS=0
check() { # check <PASS|FAIL|SKIP> <text>
  N=$((N + 1))
  printf '%d. %s %s\n' "$N" "$1" "$2"
  [ "$1" != FAIL ] || FAILS=$((FAILS + 1))
}

# missing_from_body <issue-list>: issues in the list that the PR body does not close.
BODY_REFS=" $(printf '%s' "$BODY" | closing_refs | tr '\n' ' ' || true)"
missing_from_body() {
  local i out=""
  for i in $1; do
    case "$BODY_REFS" in *" $i "*) : ;; *) out="$out #$i" ;; esac
  done
  printf '%s' "${out# }"
}

echo "sf-epic-gate: $REPO#$PR ($HEAD_REF -> $BASE_REF, head $HEAD_SHA)"

case "$HEAD_REF" in
  epic/?*) check PASS "head branch is epic/*: $HEAD_REF" ;;
  *) check FAIL "head branch must be epic/*: $HEAD_REF" ;;
esac

DEFAULT_BRANCH=$(api "repos/$REPO" | jq -r '.default_branch')
if [ "$BASE_REF" = "$DEFAULT_BRANCH" ]; then
  check PASS "base is the default branch: $BASE_REF"
else
  check FAIL "base is $BASE_REF, default branch is $DEFAULT_BRANCH (GitHub will not auto-close the issues)"
fi

LINKED=$(jq -r '.[] | select(.merged_at) | (.body // "")' <<<"$TICKET_PRS" | closing_refs || true)
MISSING=$(missing_from_body "$LINKED")
if [ -z "$MISSING" ]; then
  # shellcheck disable=SC2086
  check PASS "body closes every issue merged into the epic branch: $([ -n "$LINKED" ] && printf '#%s ' $LINKED || echo none)"
else
  check FAIL "body lacks a Closes/Fixes/Resolves line for: $MISSING"
fi

if [ -z "$PARENT" ]; then
  check SKIP "child issues of the parent (no --parent given)"
else
  MISSING=$(missing_from_body "$CHILDREN")
  if [ -z "$MISSING" ]; then
    check PASS "body closes every child issue of #$PARENT"
  else
    check FAIL "body lacks a Closes/Fixes/Resolves line for children of #$PARENT: $MISSING"
  fi
fi

if [ -z "$E2E_WF" ]; then
  check FAIL "no e2eWorkflow configured for $REPO in $CONFIG"
else
  WF_ENC=$(jq -rn --arg s "$E2E_WF" '$s|@uri')
  RUNS=$(api "repos/$REPO/actions/workflows/$WF_ENC/runs?head_sha=$HEAD_SHA&per_page=100")
  OK=$(jq -r --arg sha "$HEAD_SHA" '[.workflow_runs[] | select(.head_sha == $sha and .status == "completed" and .conclusion == "success")] | length' <<<"$RUNS")
  if [ "$OK" -gt 0 ]; then
    check PASS "E2E workflow $E2E_WF succeeded on $HEAD_SHA"
  else
    SEEN=$(jq -r --arg sha "$HEAD_SHA" '[.workflow_runs[] | select(.head_sha == $sha) | (.status + "/" + (.conclusion // "-"))] | join(", ")' <<<"$RUNS")
    if [ -z "$SEEN" ] && [ "$DISPATCH" -eq 1 ]; then
      "$GH" workflow run "$E2E_WF" --repo "$REPO" --ref "$HEAD_REF" >/dev/null || die "could not dispatch $E2E_WF on $HEAD_REF"
      check FAIL "E2E workflow $E2E_WF dispatched on $HEAD_REF; rerun the gate when it finishes"
    elif [ -z "$SEEN" ]; then
      check FAIL "no E2E run of $E2E_WF on $HEAD_SHA (pass --dispatch to start one)"
    else
      check FAIL "E2E workflow $E2E_WF has no success on $HEAD_SHA (runs: $SEEN)"
    fi
  fi
fi

if [ "$FAILS" -eq 0 ]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL ($FAILS failed)"
exit 1
