#!/usr/bin/env bash
# sf-sync-upstream.sh - merge kunchenguid/firstmate into this fork.
#
# Usage:
#   factory/bin/sf-sync-upstream.sh
#
# Runs `git fetch upstream` and `git merge upstream/main`, never a rebase and
# never a force, so every home can keep fast-forwarding from the fork.
# Afterwards it reruns bin/fm-doc-audience-check.sh and every factory/tests/*.test.sh.
# It does not push; push the merged branch yourself without --force.
# On a merge conflict it stops with the merge open for you to resolve; in
# docs/documentation-audiences.json keep both sides in sorted path order.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

git remote get-url upstream >/dev/null 2>&1 || {
  echo "error: no 'upstream' remote; see factory/docs/fork-remotes.md" >&2
  exit 1
}
[ -z "$(git status --porcelain)" ] || {
  echo "error: working tree is not clean; commit or remove changes first" >&2
  exit 1
}

git fetch upstream
git merge upstream/main || {
  echo "error: merge stopped; resolve the conflicts, commit, then rerun the checks" >&2
  exit 1
}

bin/fm-doc-audience-check.sh
for t in factory/tests/*.test.sh; do
  echo "== $t"
  bash "$t"
done
echo "synced: upstream/main merged and checks passed; push without --force"
