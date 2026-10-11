#!/usr/bin/env bash
# Tests for factory/bin/sf-review-base.sh and factory/bin/sf-review-scope-check.sh.
# Run: bash factory/tests/sf-review-base.test.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=$here/../bin
fx=$here/fixtures
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
check() { # check <name> <expected> <actual>
  [ "$2" = "$3" ] || fail "$1: expected [$2] got [$3]"
  pass=$((pass + 1))
}

# --- sf-review-base.sh ---
export FM_HOME=$tmp/home
mkdir -p "$FM_HOME/state"
cp "$fx/task.meta" "$FM_HOME/state/epic-task.meta"

out=$("$bin/sf-review-base.sh" epic-task --intent "Add the widget.")
check "meta base" "base: develop" "$(sed -n 1p <<<"$out")"
check "scope sentence" \
  "scope: Review scope: only the changes in git diff origin/develop...HEAD; files outside that diff are not part of this task." \
  "$(sed -n 2p <<<"$out")"
case "$(sed -n 3p <<<"$out")" in
  "command: no-mistakes axi run --base-branch develop --intent "*"Review\ scope:"*) pass=$((pass + 1)) ;;
  *) fail "command line: $(sed -n 3p <<<"$out")" ;;
esac

# The printed command must round-trip through the shell as real arguments.
cmd=$(sed -n 's/^command: //p' <<<"$out")
args=$(eval "set -- ${cmd#no-mistakes axi run }; printf '%s|' \"\$@\"")
check "argv" "--base-branch|develop|--intent|Add the widget. Review scope: only the changes in git diff origin/develop...HEAD; files outside that diff are not part of this task.|" "$args"

# No meta and no PR: default branch, plain command, no scope sentence.
out=$("$bin/sf-review-base.sh" unknown-task)
check "default base" "base: default" "$(sed -n 1p <<<"$out")"
check "default has no scope line" "2" "$(wc -l <<<"$out" | tr -d ' ')"
case "$out" in *"--base-branch"*) fail "default must not pass --base-branch" ;; esac

# PR fallback through a stub gh.
cat >"$tmp/gh" <<'GH'
#!/usr/bin/env bash
[ "$1 $2 $3" = "pr view 42" ] || exit 1
echo epic/widgets
GH
chmod +x "$tmp/gh"
out=$(SF_GH=$tmp/gh "$bin/sf-review-base.sh" unknown-task --pr 42)
check "pr base" "base: epic/widgets" "$(sed -n 1p <<<"$out")"

# Meta wins over the PR.
out=$(SF_GH=$tmp/gh "$bin/sf-review-base.sh" epic-task --pr 42)
check "meta beats pr" "base: develop" "$(sed -n 1p <<<"$out")"

# Bad input.
check "bad id exit" "2" "$(set +e; "$bin/sf-review-base.sh" '../evil' 2>/dev/null; echo $?)"
check "no args exit" "2" "$(set +e; "$bin/sf-review-base.sh" 2>/dev/null; echo $?)"

# --- sf-review-scope-check.sh ---
repo=$tmp/repo
git init -q -b develop "$repo"
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name t
mkdir -p "$repo/docs" "$repo/src/shared"
echo a >"$repo/docs/other-ticket.txt"
echo a >"$repo/src/shared/util.sh"
echo a >"$repo/README.dev"
git -C "$repo" add -A
git -C "$repo" commit -q -m base
git -C "$repo" update-ref refs/remotes/origin/develop HEAD
git -C "$repo" checkout -q -b feature
echo b >"$repo/src/feature.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m feature

cd "$repo"
rc=0
out=$("$bin/sf-review-scope-check.sh" "$fx/findings-mixed.toon" origin/develop 2>/dev/null) || rc=$?
check "mixed exit" "1" "$rc"
check "mixed output" "OUT-OF-DIFF 2 docs/other-ticket.txt
OUT-OF-DIFF 3 src/shared/util.sh
OUT-OF-DIFF 4 README.dev" "$out"

rc=0
out=$("$bin/sf-review-scope-check.sh" "$fx/findings-clean.toon" origin/develop 2>/dev/null) || rc=$?
check "clean exit" "0" "$rc"
check "clean output" "" "$out"

rc=0
"$bin/sf-review-scope-check.sh" "$fx/findings-clean.toon" origin/nope >/dev/null 2>&1 || rc=$?
check "bad ref exit" "2" "$rc"
rc=0
"$bin/sf-review-scope-check.sh" "$tmp/missing" origin/develop >/dev/null 2>&1 || rc=$?
check "missing file exit" "2" "$rc"

echo "sf-review-base tests: $pass passed"
