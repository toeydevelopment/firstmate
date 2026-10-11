#!/usr/bin/env bash
# Fixture-backed stand-in for gh. Serves JSON from $SF_FIXTURES, logs every call to $SF_GH_LOG.
set -eu
echo "$*" >> "${SF_GH_LOG:?}"
if [ "$1" = workflow ]; then
  [ ! -e "$SF_FIXTURES/dispatch-fails" ] || { echo "dispatch refused" >&2; exit 1; }
  exit 0
fi
[ "$1" = api ] || { echo "fake gh: unsupported: $*" >&2; exit 1; }
ep=""
for a in "$@"; do case "$a" in repos/*) ep=$a ;; esac; done
path=${ep%%\?*}
case "$path" in
  repos/*/*/pulls) f=pulls-list.json ;;
  repos/*/*/pulls/*) f=pull-${path##*/}.json ;;
  repos/*/*/issues/*/sub_issues) f=sub_issues.json ;;
  repos/*/*/actions/workflows/*/runs) f=runs.json ;;
  repos/*/*) f=repo.json ;;
  *) f=missing ;;
esac
[ -f "$SF_FIXTURES/$f" ] || { echo "fake gh: no fixture $f for $ep" >&2; exit 1; }
cat "$SF_FIXTURES/$f"
