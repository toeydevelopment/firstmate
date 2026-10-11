#!/usr/bin/env bash
# sf-runner-sample.sh - read-only health sample of a self-hosted runner machine.
#
# Usage:
#   factory/bin/sf-runner-sample.sh [--print]
#
# Samples disk use, tmpfs use, available memory, the busy-job count and the
# autoscaler's last skip reason in one ssh call. It prints one wake line only
# when a threshold from runners.env is crossed, or when the machine cannot be
# reached, so it can run as a firstmate custom check (see factory/docs/runners.md).
# With --print it prints every sampled value and ignores the back-off.
# It never changes caps, restarts anything or cleans anything.
#
# Config: $SF_RUNNERS_ENV, else $FM_HOME/config/runners.env (see
# factory/config-templates/runners.env for every key). Back-off marker:
# $SF_RUNNER_STATE_DIR (default $FM_HOME/state)/sf-runner-sample.next holds the
# earliest epoch of the next wake line.
# $FM_HOME defaults to this checkout. $SF_NOW overrides the clock for tests.
set -u

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FM_HOME="${FM_HOME:-$CODE_ROOT}"
ENV_FILE="${SF_RUNNERS_ENV:-$FM_HOME/config/runners.env}"

PRINT=0
case "${1:-}" in
  --print) PRINT=1 ;;
  "") ;;
  *) echo "usage: sf-runner-sample.sh [--print]" >&2; exit 2 ;;
esac

[ -f "$ENV_FILE" ] || { echo "error: $ENV_FILE is missing; copy factory/config-templates/runners.env there" >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

need() { [ -n "${!1:-}" ] || { echo "error: $1 is not set in $ENV_FILE" >&2; exit 1; }; }
for key in SF_RUNNER_SSH SF_RUNNER_AUTOSCALE_UNIT SF_RUNNER_DISK_PATH SF_RUNNER_TMPFS_PATH \
  SF_RUNNER_DISK_PCT_MAX SF_RUNNER_TMPFS_PCT_MAX SF_RUNNER_MEM_AVAIL_MB_MIN SF_RUNNER_BUSY_MAX; do
  need "$key"
done
BACKOFF="${SF_RUNNER_BACKOFF_SECONDS:-1200}"
SSH_TIMEOUT="${SF_RUNNER_SSH_TIMEOUT:-20}"

# Values go into a remote command line, so allow only plain characters.
safe() { case "$2" in *[!A-Za-z0-9_./@:-]*) echo "error: $1 holds an unsafe character" >&2; exit 1 ;; esac; }
for key in SF_RUNNER_SSH SF_RUNNER_AUTOSCALE_UNIT SF_RUNNER_DISK_PATH SF_RUNNER_TMPFS_PATH; do
  safe "$key" "${!key}"
done
for key in SF_RUNNER_DISK_PCT_MAX SF_RUNNER_TMPFS_PCT_MAX SF_RUNNER_MEM_AVAIL_MB_MIN SF_RUNNER_BUSY_MAX BACKOFF SSH_TIMEOUT; do
  case "${!key}" in ''|*[!0-9]*) echo "error: $key must be a whole number" >&2; exit 1 ;; esac
done

STATE="${SF_RUNNER_STATE_DIR:-$FM_HOME/state}"
NEXT="$STATE/sf-runner-sample.next"
NOW="${SF_NOW:-$(date +%s)}"

if [ "$PRINT" -eq 0 ]; then
  due=0
  [ ! -f "$NEXT" ] || IFS= read -r due < "$NEXT" || due=0
  case "$due" in ''|*[!0-9]*) due=0 ;; esac
  [ "$NOW" -ge "$due" ] || exit 0
fi

REMOTE="df -P $SF_RUNNER_DISK_PATH | awk 'NR==2{gsub(\"%\",\"\",\$5);print \"disk_pct=\"\$5}'; \
df -P $SF_RUNNER_TMPFS_PATH | awk 'NR==2{gsub(\"%\",\"\",\$5);print \"tmpfs_pct=\"\$5}'; \
awk '/^MemAvailable:/{print \"mem_avail_mb=\"int(\$2/1024)}' /proc/meminfo; \
echo \"busy=\$(pgrep -fc '[R]unner.Worker')\"; \
echo \"skip=\$(journalctl -u $SF_RUNNER_AUTOSCALE_UNIT -n 60 --no-pager 2>/dev/null | grep -i skip | tail -n 1 | cut -c1-200)\""

OUT=$(ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SF_RUNNER_SSH" "$REMOTE" 2>/dev/null) && rc=0 || rc=$?
# pgrep -c exits 1 when it counts zero, so only a missing sample means failure.
disk=$(printf '%s\n' "$OUT" | sed -n 's/^disk_pct=//p' | head -n 1)
tmpfs=$(printf '%s\n' "$OUT" | sed -n 's/^tmpfs_pct=//p' | head -n 1)
mem=$(printf '%s\n' "$OUT" | sed -n 's/^mem_avail_mb=//p' | head -n 1)
busy=$(printf '%s\n' "$OUT" | sed -n 's/^busy=//p' | head -n 1)
skip=$(printf '%s\n' "$OUT" | sed -n 's/^skip=//p' | head -n 1)

if [ "$PRINT" -eq 1 ]; then
  printf 'ssh_exit=%s\ndisk_pct=%s\ntmpfs_pct=%s\nmem_avail_mb=%s\nbusy=%s\nskip=%s\n' \
    "$rc" "$disk" "$tmpfs" "$mem" "$busy" "$skip"
  exit 0
fi

reasons=""
add() { reasons="${reasons:+$reasons; }$1"; }
num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
if ! num "$disk" || ! num "$tmpfs" || ! num "$mem" || ! num "$busy"; then
  add "runner machine unreachable or sample incomplete (ssh exit $rc)"
else
  [ "$disk" -ge "$SF_RUNNER_DISK_PCT_MAX" ] && add "disk ${disk}% >= ${SF_RUNNER_DISK_PCT_MAX}%"
  [ "$tmpfs" -ge "$SF_RUNNER_TMPFS_PCT_MAX" ] && add "tmpfs ${tmpfs}% >= ${SF_RUNNER_TMPFS_PCT_MAX}%"
  [ "$mem" -lt "$SF_RUNNER_MEM_AVAIL_MB_MIN" ] && add "MemAvailable ${mem}MB < ${SF_RUNNER_MEM_AVAIL_MB_MIN}MB"
  [ "$busy" -ge "$SF_RUNNER_BUSY_MAX" ] && add "busy jobs ${busy} >= ${SF_RUNNER_BUSY_MAX}"
fi
[ -n "$reasons" ] || exit 0

mkdir -p "$STATE"
printf '%s\n' "$((NOW + BACKOFF))" > "$NEXT"
printf 'runner health: %s; last autoscaler skip: %s; inspect with the sf-runner-ops skill (read-only first, no change without the captain)\n' \
  "$reasons" "${skip:-none logged}"
