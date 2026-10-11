#!/usr/bin/env bash
# sf-layout.test.sh - fail if this branch touches a path outside the overlay.
#
# Usage:
#   bash factory/tests/sf-layout.test.sh
#
# Compares HEAD with upstream/main (origin/main when there is no upstream
# remote) and allows only factory/, skills/sf-*, .claude-plugin/,
# .github/workflows/sf-*, and docs/documentation-audiences.json.
# SF_LAYOUT_ROOT picks the repository and SF_LAYOUT_BASE the base ref.
set -eu

ROOT="${SF_LAYOUT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT"

BASE="${SF_LAYOUT_BASE:-}"
if [ -z "$BASE" ]; then
  if git rev-parse --verify -q upstream/main >/dev/null; then
    BASE=upstream/main
  else
    BASE=origin/main
  fi
fi
git rev-parse --verify -q "$BASE" >/dev/null || {
  echo "FAIL: base ref $BASE does not exist" >&2
  exit 1
}

bad=$(git diff "$BASE...HEAD" --name-only | grep -Ev \
  '^(factory/|skills/sf-|\.claude-plugin/|\.github/workflows/sf-|docs/documentation-audiences\.json$)' || true)
if [ -n "$bad" ]; then
  echo "FAIL: paths outside the overlay allowlist (diff against $BASE):" >&2
  printf '%s\n' "$bad" >&2
  exit 1
fi
echo "ok: sf-layout (base $BASE)"
