#!/usr/bin/env bash
# sf-guard.test.sh - feed sample PreToolUse JSON to factory/hooks/sf-guard.sh.
#
# Usage:
#   bash factory/tests/sf-guard.test.sh
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../hooks/sf-guard.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

run() {  # <json> -> exit code of the guard
  local rc=0
  printf '%s' "$1" | "$GUARD" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
expect() {  # <block|allow> <label> <json>
  local rc; rc=$(run "$3")
  case "$1:$rc" in
    block:2|allow:0) ;;
    *) fail "$2 expected $1, got exit $rc" ;;
  esac
}
rd() { jq -nc --arg f "$1" '{tool_name:"Read",cwd:"/work/proj",tool_input:{file_path:$f}}'; }
bash_() { jq -nc --arg c "$1" '{tool_name:"Bash",cwd:"/work/proj",tool_input:{command:$c}}'; }
wr() { jq -nc --arg c "$1" '{tool_name:"Write",cwd:"/work/proj",tool_input:{file_path:"/work/proj/a.txt",content:$c}}'; }

# secret reads
for f in /work/proj/.env /work/proj/.env.production /home/u/key.pem /home/u/.ssh/id_rsa /home/u/.ssh/id_ed25519 /home/u/.credentials.json /home/u/.config/app/token.json; do
  expect block "read $f" "$(rd "$f")"
done
for f in /work/proj/.env.example /home/u/.ssh/id_rsa.pub /work/proj/src/main.go /home/u/.config/gh/hosts.yml; do
  expect allow "read $f" "$(rd "$f")"
done
expect block "cat .env" "$(bash_ 'cat .env')"
expect block "grep in quoted pem" "$(bash_ "grep KEY 'certs/server.pem' | head")"
expect block "redirect from id_rsa" "$(bash_ 'base64 < ~/.ssh/id_rsa')"
expect allow "ls .env is not a read" "$(bash_ 'ls -la .env')"
expect allow "cat source" "$(bash_ 'cat src/main.go')"

# literal secrets in writes
expect block "write AWS key" "$(wr 'key=AKIAABCDEFGHIJKLMNOP')"
expect block "write GitHub token" "$(wr "t=ghp_$(printf 'a%.0s' $(seq 36))")"
expect block "write private key block" "$(wr '-----BEGIN RSA PRIVATE KEY-----')"
expect block "edit new_string" "$(jq -nc '{tool_name:"Edit",cwd:"/work/proj",tool_input:{file_path:"/work/proj/a",old_string:"x",new_string:"AKIAABCDEFGHIJKLMNOP"}}')"
expect block "multiedit" "$(jq -nc '{tool_name:"MultiEdit",cwd:"/work/proj",tool_input:{file_path:"/work/proj/a",edits:[{old_string:"x",new_string:"AKIAABCDEFGHIJKLMNOP"}]}}')"
expect allow "write plain text" "$(wr 'API_KEY=${API_KEY}')"

# rm outside the project root
expect block "rm absolute outside" "$(bash_ 'rm -rf /etc/x')"
expect block "rm dotdot escape" "$(bash_ 'rm ../other/file')"
expect block "rm home" "$(bash_ 'ls && rm -rf ~/data')"
expect block "rm variable" "$(bash_ 'rm -rf $TARGET')"
expect allow "rm inside root" "$(bash_ 'rm -rf build/ /work/proj/tmp')"
expect allow "no rm" "$(bash_ 'git status')"

# firstmate exceptions
export FM_HOME=/fm
expect allow "FM_HOME state file" "$(rd /fm/state/task.token)"
expect allow "FM_HOME data file" "$(bash_ 'cat /fm/data/x/credentials.json')"
expect block "FM_HOME config .env" "$(rd /fm/config/.env)"
SF_GUARD_ALLOW=/fm/config expect allow "SF_GUARD_ALLOW prefix" "$(rd /fm/config/.env)"
SF_GUARD_ALLOW=/fm/config expect block "SF_GUARD_ALLOW is not a prefix match on siblings" "$(rd /fm/config2/.env)"

# malformed input never blocks
expect allow "empty stdin" ""
expect allow "garbage stdin" "not json"
echo "ok: sf-guard"
