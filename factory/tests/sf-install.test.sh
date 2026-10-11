#!/usr/bin/env bash
# sf-install.test.sh - exercise factory/bin/sf-install.sh in a throwaway home.
#
# Usage:
#   bash factory/tests/sf-install.test.sh
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$HERE/../bin/sf-install.sh"
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sf-install.XXXXXX")
trap 'rm -rf "$HOME_DIR"' EXIT
export FM_HOME="$HOME_DIR"
fail() { echo "FAIL: $1" >&2; exit 1; }

"$INSTALL" --dry-run | grep -q '^dry-run:' || fail "dry-run did not report"
[ ! -e "$HOME_DIR/config" ] || fail "dry-run wrote files"

"$INSTALL" | grep -q '^wrote:' || fail "first install did not write"
cmp -s <(tail -n +3 "$HOME_DIR/config/brief-include.md") "$HERE/../brief-include.md" || fail "composed file lacks shared text"
"$INSTALL" | grep -q '^unchanged:' || fail "second install was not idempotent"

echo 'Private rule.' > "$HOME_DIR/config/brief-include.private.md"
"$INSTALL" >/dev/null
tail -n 1 "$HOME_DIR/config/brief-include.md" | grep -qx 'Private rule.' || fail "private tail missing"

echo handwritten > "$HOME_DIR/config/brief-include.md"
if "$INSTALL" >/dev/null 2>&1; then fail "overwrote a hand-written file"; fi
grep -qx handwritten "$HOME_DIR/config/brief-include.md" || fail "hand-written file changed"
echo "ok: sf-install"
