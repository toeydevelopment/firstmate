#!/usr/bin/env bash
# Print the exact no-mistakes invocation a worker should use for a task, with the
# task's real base branch and the review-scope sentence.
#
# Usage: factory/bin/sf-review-base.sh <task-id> [--pr <number-or-url>] [--repo <owner/name>] [--intent <text>]
#
# Base resolution, first match wins:
#   1. base_branch= in $FM_HOME/state/<task-id>.meta (FM_HOME must be set).
#   2. The base of the pull request named by --pr, read with gh (SF_GH overrides the gh binary).
#   3. None: the task targets the repository default branch, so no base flag and no
#      scope sentence are needed and the plain invocation is printed.
#
# Output (stdout, one fact per line):
#   base: <branch>|default
#   scope: <sentence>            only when a non-default base was resolved
#   command: no-mistakes axi run [--base-branch <branch>] --intent <text>
#
# --intent supplies the goal text; without it the command carries the literal
# placeholder <goal>. The scope sentence is always appended to the intent.
# no-mistakes has no flag, environment variable or git config that makes the review
# step diff against the run base; see factory/docs/review-base.md.
# Exit: 0 printed, 2 usage or unresolvable input.
set -euo pipefail

die() { echo "sf-review-base: $*" >&2; exit 2; }

task="" pr="" repo="" intent="<goal>"
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) [ $# -ge 2 ] || die "--pr needs a value"; pr=$2; shift 2 ;;
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; repo=$2; shift 2 ;;
    --intent) [ $# -ge 2 ] || die "--intent needs a value"; intent=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown flag $1" ;;
    *) [ -z "$task" ] || die "unexpected argument $1"; task=$1; shift ;;
  esac
done
[ -n "$task" ] || die "usage: sf-review-base.sh <task-id> [--pr N] [--repo O/R] [--intent TEXT]"
case "$task" in *[!A-Za-z0-9._-]*|.*) die "invalid task id: $task" ;; esac

base=""
if [ -n "${FM_HOME:-}" ] && [ -f "$FM_HOME/state/$task.meta" ]; then
  base=$(sed -n 's/^base_branch=//p' "$FM_HOME/state/$task.meta" | tail -n 1)
fi
if [ -z "$base" ] && [ -n "$pr" ]; then
  gh_bin=${SF_GH:-gh}
  args=(pr view "$pr" --json baseRefName --jq .baseRefName)
  [ -z "$repo" ] || args+=(--repo "$repo")
  base=$("$gh_bin" "${args[@]}") || die "could not read the base of PR $pr"
fi

if [ -z "$base" ]; then
  echo "base: default"
  printf 'command: no-mistakes axi run --intent %q\n' "$intent"
  exit 0
fi

scope="Review scope: only the changes in git diff origin/$base...HEAD; files outside that diff are not part of this task."
echo "base: $base"
echo "scope: $scope"
printf 'command: no-mistakes axi run --base-branch %q --intent %q\n' "$base" "$intent $scope"
