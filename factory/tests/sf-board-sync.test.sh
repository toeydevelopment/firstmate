#!/usr/bin/env bash
# sf-board-sync.test.sh - exercise factory/bin/sf-board-sync.sh with recorded fixtures and a fake gh.
#
# Usage:
#   bash factory/tests/sf-board-sync.test.sh
#
# No network: SF_GH points at a fake that replays factory/tests/fixtures/board-sync/*
# and logs each call, and SF_TASKS_CMD replays a recorded task list.
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$HERE/../bin/sf-board-sync.sh"
FIX="$HERE/fixtures/board-sync"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sf-board.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

export FM_HOME="$WORK/home"
mkdir -p "$FM_HOME/config" "$FM_HOME/state" "$FM_HOME/data/t-merged"
cp "$FIX/boards.json" "$FM_HOME/config/boards.json"
echo 'pr=https://github.com/example-org/demo/pull/3' > "$FM_HOME/state/t-review.meta"
printf 'Dev\nInvoice totals now show tax\n' > "$FM_HOME/data/t-merged/to-try.txt"

LOG="$WORK/gh.log"
FAKE_GH="$WORK/gh"
cat > "$FAKE_GH" <<FAKE
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "api rate_limit") echo "\${FAKE_REMAINING:-4000}" ;;
  "project view") cat "$FIX/project-view.json" ;;
  "project field-list") cat "$FIX/field-list.json" ;;
  "project item-create"|"project item-add") cat "$FIX/item.json" ;;
  "project item-edit") [ -z "\${FAKE_FAIL:-}" ] || { echo "GraphQL: API rate limit already exceeded" >&2; exit 1; } ;;
  *) echo "unexpected: \$*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$FAKE_GH"
cat > "$WORK/tasks" <<TASKS
#!/usr/bin/env bash
cat "$FIX/tasks.toon"
TASKS
chmod +x "$WORK/tasks"
export SF_GH="$FAKE_GH" SF_TASKS_CMD="$WORK/tasks"
count() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }

# 1. dry run: plans four cards and one to-try, touches no API and no cache entry.
out=$("$SYNC")
[ "$(count)" = 0 ] || fail "dry run called gh"
echo "$out" | grep -q 'card t-flight -> In progress' || fail "t-flight not planned In progress"
echo "$out" | grep -q 'card t-review -> In review' || fail "meta pr= not planned In review"
echo "$out" | grep -q 'card t-held -> Waiting on captain' || fail "held not planned Waiting on captain"
echo "$out" | grep -q 'to-try t-merged' || fail "to-try card not planned"
echo "$out" | grep -q 't-queued' && fail "queued task got a card"
echo "$out" | grep -q 't-report' && fail "never-tracked done task was backfilled"
echo "$out" | grep -q 't-merged -> Done' && fail "untracked done task got a tracker card"
jq -e '.tasks == {}' "$FM_HOME/state/board-cache/boards.json" >/dev/null || fail "dry run changed the cache"

# 2. apply: cards created and fields set from the recorded ids.
"$SYNC" --apply >/dev/null || { cat "$LOG" >&2; fail "apply failed"; }
grep -q '^project item-create 1 --owner example-org --title t-flight: Add widget search' "$LOG" || fail "draft not created"
grep -q 'item-edit --project-id PVT_tracker --id PVTI_item --field-id F_status --single-select-option-id O_prog' "$LOG" || fail "status option not set"
grep -q 'field-id F_update --text https://github.com/example-org/demo/pull/3' "$LOG" || fail "PR url not written to Update"
grep -q '^project item-add 2 --owner example-org --url https://github.com/example-org/demo/pull/7' "$LOG" || fail "to-try PR not added"
grep -q 'field-id F_where --text Dev' "$LOG" || fail "Where to try not set"
grep -q 'field-id F_changed --text Invoice totals now show tax' "$LOG" || fail "What changed not set"
grep -q 'single-select-option-id O_try' "$LOG" || fail "To try status not set"
[ "$(grep -c 'field-list' "$LOG")" = 2 ] || fail "field ids should be fetched once per board"
jq -e '.tasks["t-held"].status == "waiting_on_captain" and .tasks["t-merged"].to_try == "PVTI_item"' \
  "$FM_HOME/state/board-cache/boards.json" >/dev/null || fail "cache lacks pushed state"

# 3. idempotent: nothing changed means no gh call at all.
: > "$LOG"
"$SYNC" --apply | grep -q '^unchanged' || fail "second run was not a no-op"
[ "$(count)" = 0 ] || fail "unchanged run called gh"

# 4. one task changes: only its edit is sent, ids come from the cache.
sed 's/^  t-flight,in_flight/  t-flight,done/' "$FIX/tasks.toon" > "$WORK/tasks.toon"
cat > "$WORK/tasks" <<TASKS
#!/usr/bin/env bash
cat "$WORK/tasks.toon"
TASKS
"$SYNC" --apply >/dev/null || { cat "$LOG" >&2; fail "apply failed"; }
[ "$(grep -c 'field-list\|project view\|item-create' "$LOG")" = 0 ] || fail "cached ids were refetched"
[ "$(grep -c 'item-edit' "$LOG")" = 1 ] || fail "expected exactly one edit"
grep -q 'O_done' "$LOG" || fail "merged task not moved to Done"

# 5. rate limit: low budget stops with 75 and leaves the diff for next time.
: > "$LOG"
sed 's/^  t-held,queued/  t-held,in_flight/' "$WORK/tasks.toon" | sed 's/,yes,none/,no,none/' > "$WORK/tasks2.toon"
cp "$WORK/tasks2.toon" "$WORK/tasks.toon"
set +e; FAKE_REMAINING=10 "$SYNC" --apply >/dev/null 2>"$WORK/err"; rc=$?; set -e
[ "$rc" = 75 ] || fail "low budget exited $rc, want 75"
[ "$(grep -c 'item-edit' "$LOG")" = 0 ] || fail "wrote despite low budget"
set +e; FAKE_FAIL=1 "$SYNC" --apply >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 75 ] || fail "rate-limit error exited $rc, want 75"
jq -e '.tasks["t-held"].status == "waiting_on_captain"' "$FM_HOME/state/board-cache/boards.json" >/dev/null \
  || fail "failed edit was cached as pushed"
"$SYNC" --apply | grep -q 'applied: card t-held -> in_progress' || fail "next run did not resume"

# 6. config errors.
rm "$FM_HOME/config/boards.json"
set +e; "$SYNC" >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = 2 ] || fail "missing config exited $rc, want 2"
echo "ok: sf-board-sync"
