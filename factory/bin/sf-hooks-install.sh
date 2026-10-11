#!/usr/bin/env bash
# sf-hooks-install.sh - merge the factory guard hook into a Claude Code settings.json.
#
# Usage:
#   factory/bin/sf-hooks-install.sh <settings.json> [--apply]
#
# Dry run by default: prints the diff the merge would make and writes nothing.
# With --apply it first copies an existing file to <settings.json>.sf-bak, then
# writes the merged result. Running it again changes nothing, because the hook is
# recognised by its command path. Other settings and hooks are preserved.
# A missing target is treated as an empty settings object.
# Never run automatically: the caller names the target, for example
# .claude/settings.json in one project or ~/.claude/settings.json by choice.
# Requires jq.
set -eu

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$CODE_ROOT/factory/hooks/sf-guard.sh"
MATCHER='Read|Write|Edit|MultiEdit|Bash'

TARGET=${1:-}
APPLY=0
case "${2:-}" in
  --apply) APPLY=1 ;;
  "") ;;
  *) TARGET="" ;;
esac
[ -n "$TARGET" ] || { echo "usage: sf-hooks-install.sh <settings.json> [--apply]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
[ -x "$HOOK" ] || { echo "error: $HOOK is missing or not executable" >&2; exit 1; }

CURRENT=$(mktemp "${TMPDIR:-/tmp}/sf-hooks.XXXXXX")
MERGED=$(mktemp "${TMPDIR:-/tmp}/sf-hooks.XXXXXX")
trap 'rm -f "$CURRENT" "$MERGED"' EXIT
if [ -f "$TARGET" ]; then cp "$TARGET" "$CURRENT"; else echo '{}' > "$CURRENT"; fi
jq -e 'type == "object"' "$CURRENT" >/dev/null 2>&1 || { echo "error: $TARGET is not a JSON object" >&2; exit 1; }

jq -S --arg cmd "$HOOK" --arg matcher "$MATCHER" '
  if any((.hooks.PreToolUse // [])[]?; any(.hooks[]?; .command == $cmd)) then .
  else .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{matcher: $matcher, hooks: [{type: "command", command: $cmd}]}])
  end' "$CURRENT" > "$MERGED"

if jq -S . "$CURRENT" | cmp -s - "$MERGED"; then
  echo "unchanged: $TARGET"
  exit 0
fi
diff -u <(jq -S . "$CURRENT") "$MERGED" | tail -n +3 || true
if [ "$APPLY" -eq 1 ]; then
  [ ! -f "$TARGET" ] || cp "$TARGET" "$TARGET.sf-bak"
  cp "$MERGED" "$TARGET"
  echo "wrote: $TARGET"
else
  echo "dry-run: would write $TARGET (rerun with --apply)"
fi
