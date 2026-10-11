#!/usr/bin/env bash
# List review findings that cite files outside the task's own diff.
#
# Usage: factory/bin/sf-review-scope-check.sh <findings-file> <base-ref>
#
# Run it from inside the task's worktree. <findings-file> is any text a reviewer
# produced (for example a saved `no-mistakes axi status` output); <base-ref> is the
# task's real base, such as origin/develop. A token in the findings counts as a cited
# file when it is a path that exists in HEAD or in <base-ref>; free text, versions and
# URLs are ignored. A cited file absent from `git diff --name-only <base-ref>...HEAD`
# is reported as one line on stdout:
#   OUT-OF-DIFF <findings-line-number> <file>
# A finding that cites both in-diff and out-of-diff files still reports its
# out-of-diff files, so read the finding before dismissing it.
# Exit: 0 nothing outside the diff, 1 at least one file outside, 2 usage or git error.
set -euo pipefail

die() { echo "sf-review-scope-check: $*" >&2; exit 2; }

[ $# -eq 2 ] || die "usage: sf-review-scope-check.sh <findings-file> <base-ref>"
findings=$1 base=$2
[ -f "$findings" ] || die "findings file not found: $findings"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "unknown base ref: $base"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git ls-tree -r --name-only HEAD >"$tmp/tracked"
git ls-tree -r --name-only "$base" >>"$tmp/tracked"
git diff --name-only "$base...HEAD" >"$tmp/diff"

awk -v tracked="$tmp/tracked" -v diff="$tmp/diff" '
  BEGIN {
    while ((getline f < tracked) > 0) known[f] = 1
    while ((getline f < diff) > 0) changed[f] = 1
  }
  {
    line = $0
    gsub(/[^A-Za-z0-9_@.+\/-]/, " ", line)
    n = split(line, tok, " ")
    for (i = 1; i <= n; i++) {
      t = tok[i]
      sub(/^\.\//, "", t)
      sub(/[.]+$/, "", t)
      if (t in known && !(t in changed) && !((NR SUBSEP t) in seen)) {
        seen[NR SUBSEP t] = 1
        print "OUT-OF-DIFF " NR " " t
      }
    }
  }
' "$findings" >"$tmp/out"

cat "$tmp/out"
if [ -s "$tmp/out" ]; then
  echo "sf-review-scope-check: $(wc -l <"$tmp/out") cited file(s) outside git diff $base...HEAD" >&2
  exit 1
fi
