#!/usr/bin/env bash
# sf-layout-fixture.test.sh - prove sf-layout.test.sh passes and fails correctly.
#
# Usage:
#   bash factory/tests/sf-layout-fixture.test.sh
#
# Builds a throwaway repository, then runs the layout test against an
# overlay-only branch (must pass) and a branch that edits an upstream file
# (must fail).
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/sf-layout.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q -b main .
git config user.email t@example.invalid
git config user.name t
mkdir bin docs
echo base > bin/tool.sh
echo '{}' > docs/documentation-audiences.json
git add -A && git commit -q -m base

git checkout -q -b good
mkdir -p factory skills/sf-x .github/workflows
echo a > factory/README.md
echo b > skills/sf-x/SKILL.md
echo c > .github/workflows/sf-overlay-check.yml
echo '{"v":1}' > docs/documentation-audiences.json
git add -A && git commit -q -m overlay
SF_LAYOUT_ROOT="$TMP" SF_LAYOUT_BASE=main bash "$HERE/sf-layout.test.sh" >/dev/null ||
  { echo "FAIL: overlay-only branch was rejected" >&2; exit 1; }

echo changed > bin/tool.sh
git add -A && git commit -q -m touch-upstream
if out=$(SF_LAYOUT_ROOT="$TMP" SF_LAYOUT_BASE=main bash "$HERE/sf-layout.test.sh" 2>&1); then
  echo "FAIL: upstream-file edit was accepted" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -qx 'bin/tool.sh' || { echo "FAIL: offending path not named" >&2; exit 1; }
echo "ok: sf-layout-fixture"
