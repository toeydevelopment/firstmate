#!/usr/bin/env bash
# Tests factory/bin/sf-epic-gate.sh against recorded GitHub API JSON; no network.
# The fixtures in tests/fixtures/epic-gate/good are a passing epic; each case copies them and breaks one thing.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../bin/sf-epic-gate.sh"
FAKE="$HERE/fixtures/fake-gh.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

cat > "$TMP/config.json" <<'JSON'
{"default":{"e2eWorkflow":"e2e.yml"},"repos":{"acme/app":{"e2eWorkflow":"e2e-dispatch.yml"}}}
JSON

# scenario <name> [jq-edit-spec...]: copy the good fixtures; each spec is "<file>=<jq filter>".
scenario() {
  local name=$1 spec f
  shift
  rm -rf "${TMP:?}/$name"
  cp -R "$HERE/fixtures/epic-gate/good" "$TMP/$name"
  for spec in "$@"; do
    f=${spec%%=*}
    jq "${spec#*=}" "$TMP/$name/$f" > "$TMP/$name/$f.new" && mv "$TMP/$name/$f.new" "$TMP/$name/$f"
  done
}

# run_gate <scenario> [gate args...]: sets OUT, CODE and the call log.
run_gate() {
  local name=$1
  shift
  : > "$TMP/$name.log"
  OUT=$(SF_GH="$FAKE" SF_FIXTURES="$TMP/$name" SF_GH_LOG="$TMP/$name.log" "$GATE" --config "$TMP/config.json" "$@" 2>&1)
  CODE=$?
}

expect() { # expect <label> <exit-code> <text-in-output>...
  local label=$1 want=$2
  shift 2
  [ "$CODE" = "$want" ] || fail "$label: exit $CODE, wanted $want"$'\n'"$OUT"
  local t
  for t in "$@"; do
    case "$OUT" in *"$t"*) : ;; *) fail "$label: missing '$t'"$'\n'"$OUT" ;; esac
  done
  pass "$label"
}

scenario good
run_gate good acme/app 50
expect "good epic passes" 0 "1. PASS head branch is epic/*" "2. PASS base is the default branch: main" "3. PASS" "#1 #2 #3" "4. SKIP" "5. PASS" "RESULT: PASS"
run_gate good acme/app https://github.com/acme/app/pull/50
expect "PR URL accepted" 0 "RESULT: PASS"
run_gate good --parent 7 acme/app 50
expect "parent children all closed" 0 "4. PASS body closes every child issue of #7" "RESULT: PASS"
grep -qE '^workflow run' "$TMP/good.log" && fail "gate wrote with no --dispatch"
grep -qE '(^| )(-X|--method|-f|-F|--field|--raw-field|--input) ' "$TMP/good.log" && fail "gate issued a write request"
pass "read-only: no write calls"

scenario badhead 'pull-50.json=.head.ref="feature/demo"'
run_gate badhead acme/app 50
expect "non-epic head fails" 1 "1. FAIL head branch must be epic/*: feature/demo" "RESULT: FAIL"

scenario badbase 'pull-50.json=.base.ref="develop"'
run_gate badbase acme/app 50
expect "non-default base fails" 1 "2. FAIL base is develop, default branch is main" "auto-close"

scenario nocloses 'pull-50.json=.body="Epic demo.\nCloses #1\n"'
run_gate nocloses acme/app 50
expect "missing closing line fails" 1 "3. FAIL" "#2" "#3"
printf '%s\n' "$OUT" | grep -qE '#(9|10|99)( |$)' && fail "unmerged or cross-repo issues must not be required"
pass "unmerged and cross-repo issues not required"

scenario noparent 'sub_issues.json=. + [{"number":5,"repository_url":"https://api.github.com/repos/acme/app"}]'
run_gate noparent --parent 7 acme/app 50
expect "child without closing line fails" 1 "3. PASS" "4. FAIL" "children of #7: #5"

scenario nopass 'runs.json=.workflow_runs |= map(select(.conclusion != "success"))'
run_gate nopass acme/app 50
expect "failed-only E2E fails" 1 "5. FAIL" "no success" "completed/failure"

scenario otherhead 'runs.json=.workflow_runs |= map(.head_sha = "bbbb")'
run_gate otherhead acme/app 50
expect "E2E on another SHA fails" 1 "5. FAIL" "no E2E run" "--dispatch"
grep -qE '^workflow run' "$TMP/otherhead.log" && fail "dispatched without --dispatch"
pass "no dispatch by default"

run_gate otherhead --dispatch acme/app 50
expect "--dispatch starts the workflow" 1 "5. FAIL" "dispatched on epic/demo"
grep -qF 'workflow run e2e-dispatch.yml --repo acme/app --ref epic/demo' "$TMP/otherhead.log" || fail "dispatch call missing or wrong"
pass "dispatch call uses configured workflow and epic ref"

run_gate good --dispatch acme/app 50
expect "--dispatch skipped when a success exists" 0 "RESULT: PASS"
grep -qE '^workflow run' "$TMP/good.log" && fail "dispatched although E2E already passed"
pass "no redundant dispatch"

run_gate good --ledger acme/app 50
expect "ledger prints tickets" 0 "TICKET" "#1" "#41" "merged" "#10" "#44" "open" "(epic)" "#50"
case "$OUT" in *"#9 "*) : ;; *) fail "ledger must list the closed unmerged PR"$'\n'"$OUT" ;; esac
case "$OUT" in *"closed"*) pass "ledger shows closed PR status" ;; *) fail "closed status missing" ;; esac
run_gate noparent --ledger --parent 7 acme/app 50
expect "ledger lists child with no PR" 0 "#5" "no PR"

: > "$TMP/cfg.log"
OUT=$(SF_GH="$FAKE" SF_FIXTURES="$TMP/good" SF_GH_LOG="$TMP/cfg.log" "$GATE" --config "$TMP/missing.json" acme/app 50 2>&1); CODE=$?
expect "missing config is an error" 2 "config not found"
run_gate good acme/app notanumber
expect "bad PR argument is an error" 2 "epic PR must be"
run_gate good acme/app https://github.com/other/app/pull/50
expect "URL for another repo is an error" 2 "does not match"
rm "$TMP/good/pull-50.json"
run_gate good acme/app 50
expect "GitHub read failure is an error" 2 "GitHub read failed"
