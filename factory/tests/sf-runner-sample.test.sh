#!/usr/bin/env bash
# sf-runner-sample.test.sh - exercise factory/bin/sf-runner-sample.sh with a stubbed ssh.
#
# Usage:
#   bash factory/tests/sf-runner-sample.test.sh
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="$HERE/../bin/sf-runner-sample.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/sf-runner-sample.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state"
fail() { echo "FAIL: $1" >&2; exit 1; }

cp "$HERE/../config-templates/runners.env" "$TMP/runners.env"
# The stub ssh records its arguments and replies with the file named by STUB_REPLY.
cat > "$TMP/bin/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
[ -f "$STUB_REPLY" ] || exit 255
cat "$STUB_REPLY"
STUB
chmod +x "$TMP/bin/ssh"

export PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/ssh.log" STUB_REPLY="$TMP/reply"
export SF_RUNNERS_ENV="$TMP/runners.env" SF_RUNNER_STATE_DIR="$TMP/state" SF_NOW=1000
: > "$STUB_LOG"

reply() { printf 'disk_pct=%s\ntmpfs_pct=%s\nmem_avail_mb=%s\nbusy=%s\nskip=%s\n' "$@" > "$STUB_REPLY"; }

# Healthy sample prints nothing and writes no back-off marker.
reply 40 10 20000 1 ""
[ -z "$("$SAMPLE")" ] || fail "healthy sample woke firstmate"
[ ! -e "$TMP/state/sf-runner-sample.next" ] || fail "healthy sample wrote a back-off marker"
grep -q 'runner-vm' "$STUB_LOG" || fail "ssh was not called with the configured host"

# A crossed threshold prints exactly one line naming it and the skip reason.
reply 92 10 20000 1 "skip: not enough free disk"
out=$("$SAMPLE")
[ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || fail "wake was not one line"
case "$out" in *"disk 92% >= 85%"*"not enough free disk"*) ;; *) fail "wake lacks disk reason: $out" ;; esac

# Back-off suppresses the next wake until it expires.
reply 95 10 20000 1 ""
[ -z "$(SF_NOW=1100 "$SAMPLE")" ] || fail "back-off did not suppress the wake"
[ -n "$(SF_NOW=2300 "$SAMPLE")" ] || fail "wake did not return after back-off"
rm -f "$TMP/state/sf-runner-sample.next"

# Each other threshold wakes.
reply 40 90 20000 1 ""
case "$("$SAMPLE")" in *"tmpfs 90%"*) ;; *) fail "tmpfs threshold missed" ;; esac
rm -f "$TMP/state/sf-runner-sample.next"
reply 40 10 1000 1 ""
case "$("$SAMPLE")" in *"MemAvailable 1000MB"*) ;; *) fail "memory threshold missed" ;; esac
rm -f "$TMP/state/sf-runner-sample.next"
reply 40 10 20000 5 ""
case "$("$SAMPLE")" in *"busy jobs 5"*) ;; *) fail "busy threshold missed" ;; esac
rm -f "$TMP/state/sf-runner-sample.next"

# An unreachable machine wakes once instead of staying silent.
rm -f "$STUB_REPLY"
case "$("$SAMPLE")" in *unreachable*) ;; *) fail "unreachable machine did not wake" ;; esac
rm -f "$TMP/state/sf-runner-sample.next"

# --print shows values and ignores back-off.
reply 40 10 20000 2 "skip: cap reached"
printf '5000\n' > "$TMP/state/sf-runner-sample.next"
"$SAMPLE" --print | grep -qx 'busy=2' || fail "--print lacks busy"
"$SAMPLE" --print | grep -qx 'skip=skip: cap reached' || fail "--print lacks skip reason"

# Read-only: only ssh ran, and its remote command holds no mutating verb.
if grep -Eq 'systemctl (restart|start|stop)|rm |docker (system|volume)|virsh|sudo' "$STUB_LOG"; then
  fail "sampler sent a mutating command"
fi

# An unsafe host value is refused before ssh runs.
sed 's#^SF_RUNNER_SSH=.*#SF_RUNNER_SSH="a;b"#' "$TMP/runners.env" > "$TMP/bad.env"
: > "$STUB_LOG"
if SF_RUNNERS_ENV="$TMP/bad.env" "$SAMPLE" >/dev/null 2>&1; then fail "unsafe value accepted"; fi
[ ! -s "$STUB_LOG" ] || fail "ssh ran with an unsafe value"

echo "ok: sf-runner-sample"
