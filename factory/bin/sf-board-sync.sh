#!/usr/bin/env bash
# sf-board-sync.sh - project firstmate task state onto a GitHub Project tracker board.
#
# Usage:
#   factory/bin/sf-board-sync.sh [--apply] [--refresh]
#
# Default is a dry run: it prints the planned card changes and makes no gh call.
# --apply performs them. --refresh drops the cached project, field and option ids first.
#
# Task state comes from `bin/fm-tasks-axi.sh list --fields held,links` and the
# state/<id>.meta `pr=` record. One draft card per task, keyed by task id:
#   in flight                    -> status.in_progress
#   in flight with a PR recorded -> status.in_review
#   held for the captain         -> status.waiting_on_captain
#   done (teardown after merge)  -> status.done
# A queued task that is not held has not started and gets no card.
# A done task that never had a card is not backfilled.
# The Update field, when configured, carries the PR URL.
#
# "To try" card: when a task becomes done and data/<id>/to-try.txt exists, its PR
# (links pr:, else the meta pr=) is added to the ready-to-try board with status
# to-try, the Where-to-try field from line 1 of that file (else where_default) and
# the changed field from line 2 when present. Without a PR there is no card.
#
# Config: $FM_HOME/config/boards.json (private, gitignored). The shipped example
# is factory/config-templates/boards.json. Nothing board-specific lives in this file.
# Cache: $FM_HOME/state/board-cache/boards.json holds the ids and the last pushed
# state per task. Unchanged tasks make no API call, and a run with no change makes none at all.
# Rate limits: before writing it reads gh's GraphQL budget and stops when fewer than
# limits.min_graphql_remaining points remain. It also stops after limits.max_calls
# gh calls, and on any gh error mentioning a rate limit. The cache is saved after every
# successful call, so the next run resumes with the remaining diff.
#
# Environment: FM_HOME (default: this checkout), SF_GH (gh binary, default gh),
# SF_TASKS_CMD (default bin/fm-tasks-axi.sh), both overridable for tests.
# Exit: 0 done or nothing to do, 2 usage or config error, 75 stopped by a rate limit
# or call cap with work remaining, 1 any other gh failure.
# jq programs are single-quoted on purpose; their $names are jq variables.
# shellcheck disable=SC2016
set -eu

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FM_HOME="${FM_HOME:-$CODE_ROOT}"
GH="${SF_GH:-gh}"
TASKS_CMD="${SF_TASKS_CMD:-$CODE_ROOT/bin/fm-tasks-axi.sh}"
CONFIG="$FM_HOME/config/boards.json"
CACHE_DIR="$FM_HOME/state/board-cache"
CACHE="$CACHE_DIR/boards.json"

APPLY=0
REFRESH=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --refresh) REFRESH=1 ;;
    *) echo "usage: sf-board-sync.sh [--apply] [--refresh]" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }
[ -f "$CONFIG" ] || { echo "error: $CONFIG is missing; copy factory/config-templates/boards.json there and edit it" >&2; exit 2; }
jq -e '.owner and .tracker.number and .tracker.status_field and (.tracker.status | length > 0)' "$CONFIG" >/dev/null \
  || { echo "error: $CONFIG lacks owner, tracker.number, tracker.status_field or tracker.status" >&2; exit 2; }

cfg() { jq -r "$1" "$CONFIG"; }
OWNER=$(cfg .owner)
MIN_REMAINING=$(cfg '.limits.min_graphql_remaining // 300')
MAX_CALLS=$(cfg '.limits.max_calls // 40')

mkdir -p "$CACHE_DIR"
[ -f "$CACHE" ] || echo '{"boards":{},"tasks":{}}' > "$CACHE"
if [ "$REFRESH" -eq 1 ]; then
  jq '.boards = {}' "$CACHE" > "$CACHE.new" && mv "$CACHE.new" "$CACHE"
fi

# --- desired state, one unit-separator (0x1f) delimited row per task: id, status key, pr url, title ---
raw=$("$TASKS_CMD" list --limit 1000 --fields held,links) || { echo "error: task list failed" >&2; exit 2; }
rows=$(printf '%s\n' "$raw" | awk '
  /^  [^ ]/ {
    line = substr($0, 3)
    if (!match(line, /,(yes|no|-),("[^"]*"|[^,]*)$/)) next
    tail = substr(line, RSTART + 1); head = substr(line, 1, RSTART - 1)
    split(tail, t, ","); held = t[1]; links = substr(tail, length(held) + 2)
    split(head, h, ","); id = h[1]; state = h[2]
    title = head; sub(/^[^,]*,[^,]*,[^,]*,[^,]*,/, "", title)
    sub(/\\n\.\.\. \(truncated.*$/, "", title); gsub(/^"|"$/, "", title)
    pr = ""; if (match(links, /pr:https:\/\/[^",]*/)) pr = substr(links, RSTART + 3, RLENGTH - 3)
    printf "%s\037%s\037%s\037%s\037%s\n", id, state, held, pr, title
  }')

plan=$(mktemp "${TMPDIR:-/tmp}/sf-board.XXXXXX")
trap 'rm -f "$plan" "$CACHE.new"' EXIT

# plan lines (0x1f separated): kind, task id, status key, update text, title, pr, where, changed
while IFS=$'\037' read -r id state held pr title; do
  [ -n "$id" ] || continue
  meta="$FM_HOME/state/$id.meta"
  [ -n "$pr" ] || { [ ! -f "$meta" ] || pr=$(sed -n 's/^pr=//p' "$meta" | head -n 1); }
  if [ "$state" = "done" ]; then key="done"
  elif [ "$held" = yes ]; then key=waiting_on_captain
  elif [ "$state" = in_flight ] && [ -n "$pr" ]; then key=in_review
  elif [ "$state" = in_flight ]; then key=in_progress
  else continue; fi
  cached=$(jq -r --arg id "$id" '.tasks[$id].status // ""' "$CACHE")
  cached_update=$(jq -r --arg id "$id" '.tasks[$id].update // ""' "$CACHE")
  if [ -z "$cached" ] && [ "$key" = "done" ]; then
    :
  elif [ "$cached" != "$key" ] || [ "$cached_update" != "$pr" ]; then
    printf 'card\037%s\037%s\037%s\037%s\n' "$id" "$key" "$pr" "$title" >> "$plan"
  fi
  tried=$(jq -r --arg id "$id" '.tasks[$id].to_try // ""' "$CACHE")
  tt="$FM_HOME/data/$id/to-try.txt"
  if [ "$key" = "done" ] && [ -z "$tried" ] && [ -n "$pr" ] && [ -f "$tt" ] && [ "$(cfg '.ready_to_try.number // empty')" != "" ]; then
    where=$(sed -n 1p "$tt"); changed=$(sed -n 2p "$tt")
    [ -n "$where" ] || where=$(cfg '.ready_to_try.where_default // ""')
    printf 'totry\037%s\037%s\037%s\037%s\037%s\n' "$id" "$pr" "$where" "$changed" "$title" >> "$plan"
  fi
done <<< "$rows"

if [ ! -s "$plan" ]; then echo "unchanged: no board changes"; exit 0; fi

if [ "$APPLY" -eq 0 ]; then
  while IFS=$'\037' read -r kind id a b c _; do
    case "$kind" in
      card) echo "dry-run: card $id -> $(cfg ".tracker.status.$a") ${b:+(update: $b)}" ;;
      totry) echo "dry-run: to-try $id -> $(cfg '.ready_to_try.status_option') where=$b ${c:+changed=$c}" ;;
    esac
  done < "$plan"
  echo "dry-run: $(wc -l < "$plan" | tr -d ' ') change(s); rerun with --apply"
  exit 0
fi

# --- apply ---
CALLS=0
save() { local f="$1"; shift; jq "$@" "$f" "$CACHE" > "$CACHE.new" && mv "$CACHE.new" "$CACHE"; }
rate_stop() { echo "stopped: $1; rerun later to resume" >&2; exit 75; }

# gh wrapper: counts calls, enforces the cap, maps rate-limit errors to exit 75.
call() {
  [ "$CALLS" -lt "$MAX_CALLS" ] || rate_stop "call cap $MAX_CALLS reached"
  CALLS=$((CALLS + 1))
  local out
  if ! out=$("$GH" "$@" 2>&1); then
    case "$out" in
      *[Rr]ate\ limit*|*RATE_LIMITED*|*"API rate"*|*"HTTP 403"*) rate_stop "GitHub rate limit" ;;
    esac
    echo "error: gh $1 $2 failed: $out" >&2
    exit 1
  fi
  printf '%s' "$out"
}

remaining=$(call api rate_limit --jq .resources.graphql.remaining)
[ "$remaining" -ge "$MIN_REMAINING" ] 2>/dev/null || rate_stop "only $remaining GraphQL points left (minimum $MIN_REMAINING)"

# Cache project id and field/option ids for one board (config path prefix $1, cache key $2).
ensure_board() {
  local path="$1" key="$2" number
  number=$(cfg "$path.number")
  if [ "$(jq -r --arg k "$key" '.boards[$k] // empty | .project_id' "$CACHE")" != "" ]; then return 0; fi
  local pid fields
  pid=$(call project view "$number" --owner "$OWNER" --format json | jq -r .id)
  fields=$(call project field-list "$number" --owner "$OWNER" --format json \
    | jq -c '[.fields[] | {key: .name, value: {id: .id, opts: ([.options[]? | {key: .name, value: .id}] | from_entries)}}] | from_entries')
  save '.boards[$k] = {project_id: $p, fields: $f}' --arg k "$key" --arg p "$pid" --argjson f "$fields"
}

# Set one field on one item. $1 board key, $2 item id, $3 field name, $4 value.
set_field() {
  local bkey="$1" item="$2" fname="$3" value="$4" pid fid oid
  pid=$(jq -r --arg k "$bkey" '.boards[$k].project_id' "$CACHE")
  fid=$(jq -r --arg k "$bkey" --arg f "$fname" '.boards[$k].fields[$f].id // empty' "$CACHE")
  [ -n "$fid" ] || { echo "error: field '$fname' not on the $bkey board; check config/boards.json or rerun with --refresh" >&2; exit 1; }
  oid=$(jq -r --arg k "$bkey" --arg f "$fname" --arg v "$value" '.boards[$k].fields[$f].opts[$v] // empty' "$CACHE")
  if [ "$(jq -r --arg k "$bkey" --arg f "$fname" '.boards[$k].fields[$f].opts | length' "$CACHE")" -gt 0 ]; then
    [ -n "$oid" ] || { echo "error: option '$value' not in field '$fname'; check config/boards.json or rerun with --refresh" >&2; exit 1; }
    call project item-edit --project-id "$pid" --id "$item" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
  else
    call project item-edit --project-id "$pid" --id "$item" --field-id "$fid" --text "$value" >/dev/null
  fi
}

ensure_board .tracker tracker
UPDATE_FIELD=$(cfg '.tracker.update_field // ""')

while IFS=$'\037' read -r kind id a b c _; do
  case "$kind" in
    card)
      item=$(jq -r --arg id "$id" '.tasks[$id].item // ""' "$CACHE")
      if [ -z "$item" ]; then
        item=$(call project item-create "$(cfg .tracker.number)" --owner "$OWNER" --title "$id: $c" --format json | jq -r .id)
        save '.tasks[$id] = {item: $i}' --arg id "$id" --arg i "$item"
      fi
      cs=$(jq -r --arg id "$id" '.tasks[$id].status // ""' "$CACHE")
      if [ "$cs" != "$a" ]; then
        set_field tracker "$item" "$(cfg .tracker.status_field)" "$(cfg ".tracker.status.$a")"
        save '.tasks[$id].status = $s' --arg id "$id" --arg s "$a"
      fi
      cu=$(jq -r --arg id "$id" '.tasks[$id].update // ""' "$CACHE")
      if [ -n "$UPDATE_FIELD" ] && [ "$cu" != "$b" ] && [ -n "$b" ]; then
        set_field tracker "$item" "$UPDATE_FIELD" "$b"
      fi
      save '.tasks[$id].update = $u' --arg id "$id" --arg u "$b"
      echo "applied: card $id -> $a"
      ;;
    totry)
      ensure_board .ready_to_try ready_to_try
      item=$(call project item-add "$(cfg .ready_to_try.number)" --owner "$OWNER" --url "$a" --format json | jq -r .id)
      set_field ready_to_try "$item" "$(cfg .ready_to_try.status_field)" "$(cfg .ready_to_try.status_option)"
      set_field ready_to_try "$item" "$(cfg .ready_to_try.where_field)" "$b"
      if [ -n "$c" ]; then set_field ready_to_try "$item" "$(cfg .ready_to_try.changed_field)" "$c"; fi
      save '.tasks[$id].to_try = $i' --arg id "$id" --arg i "$item"
      echo "applied: to-try $id"
      ;;
  esac
done < "$plan"
echo "done: $CALLS gh call(s)"
