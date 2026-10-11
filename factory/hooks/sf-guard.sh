#!/usr/bin/env bash
# sf-guard.sh - Claude Code PreToolUse guard hook for factory workers.
#
# Usage (wired by factory/bin/sf-hooks-install.sh, matcher Read|Write|Edit|MultiEdit|Bash):
#   sf-guard.sh < hook-json
#
# Reads the PreToolUse JSON from stdin (tool_name, tool_input, cwd) and blocks by
# exiting 2 with the reason on stderr; any other outcome exits 0 (no decision).
# Blocks three things:
#   1. reading secret files: .env, .env.*, *.pem, id_* (not *.pub), .credentials*,
#      *credentials.json, .netrc, token / *.token / token.json files;
#   2. writing a literal API key or token (AWS, GitHub, Slack, OpenAI/Anthropic
#      style, PEM private key block) into a file via Write, Edit or MultiEdit;
#   3. rm or unlink of a path outside the project root (the hook's cwd).
# Never blocked: *.example, *.sample, *.template, *.pub, anything under
# $FM_HOME/state/ or $FM_HOME/data/ (firstmate's own state), and any path under a
# prefix listed in the colon-separated SF_GUARD_ALLOW. See factory/docs/hooks.md.
# A malformed or empty payload is not blocked, matching Claude Code's own
# "non-blocking error" semantics for hook failures.
set -uf

command -v jq >/dev/null 2>&1 || { echo "sf-guard: jq missing, guard inactive" >&2; exit 0; }
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$PWD
FM_HOME_DIR="${FM_HOME:-}"

deny() { echo "sf-guard: blocked - $1" >&2; exit 2; }

allowed_path() {  # <abs-path>
  local p=$1 pre
  if [ -n "$FM_HOME_DIR" ]; then
    case "$p" in "$FM_HOME_DIR"/state/*|"$FM_HOME_DIR"/data/*) return 0 ;; esac
  fi
  local IFS=:
  for pre in ${SF_GUARD_ALLOW:-}; do
    [ -n "$pre" ] && case "$p" in "$pre"|"$pre"/*) return 0 ;; esac
  done
  return 1
}

secret_name() {  # <path-or-token> ; true when its basename is a secret file
  local b=${1##*/}
  case "$b" in
    *.example|*.sample|*.template|*.pub) return 1 ;;
    .env|.env.*|*.pem|id_*|.credentials*|*credentials.json|.netrc|token|.token|*.token|token.json) return 0 ;;
  esac
  return 1
}

abs_path() {  # <path> -> lexically normalised absolute path
  local p=$1 out=() seg
  # shellcheck disable=SC2088  # literal tilde from the command text, expanded here on purpose
  case "$p" in "~"|"~/"*) p="${HOME:-/}${p#\~}" ;; /*) ;; *) p="$CWD/$p" ;; esac
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ""|.) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$seg") ;;
    esac
  done
  printf '/%s' "${out[@]}"; [ "${#out[@]}" -eq 0 ] && printf '/'
  printf '\n'
}

check_read_path() {  # <path>
  local p
  p=$(abs_path "$1")
  secret_name "$p" || return 0
  allowed_path "$p" && return 0
  deny "reading secret file $1"
}

SECRET_RE='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{32,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

check_write_text() {  # <text>
  printf '%s' "$1" | grep -Eq -- "$SECRET_RE" && deny "literal API key or token in file content"
  return 0
}

case "$TOOL" in
  Read)
    check_read_path "$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')" ;;
  Write|Edit|MultiEdit)
    # Only the content is scanned; writing a file named .env is not itself a read.
    check_write_text "$(printf '%s' "$INPUT" | jq -r '[.tool_input.content, .tool_input.new_string, (.tool_input.edits // [] | .[].new_string)] | map(select(. != null)) | join("\n")')" ;;
  Bash)
    cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -n "$cmd" ] || exit 0
    # Tokenise on whitespace and shell separators; quotes are stripped.
    toks=$(printf '%s' "$cmd" | tr -d '"'"'" | tr ';|&<>()`' '\n\n\n\n\n\n\n\n' | tr ' \t' '\n\n')
    reader=0
    printf '%s\n' "$cmd" | grep -Eq '(^|[;|&(`[:space:]])(cat|less|more|head|tail|grep|egrep|rg|sed|awk|cp|mv|base64|xxd|od|strings|source|bat|nl|tac|openssl|curl)[[:space:]]|(^|[;&|[:space:]])\.[[:space:]]|<[[:space:]]*[^[:space:]]' && reader=1
    if [ "$reader" -eq 1 ]; then
      while IFS= read -r t; do
        [ -n "$t" ] || continue
        secret_name "$t" || continue
        allowed_path "$(abs_path "$t")" && continue
        deny "command reads secret file $t"
      done <<< "$toks"
    fi
    # rm / unlink outside the project root.
    if printf '%s\n' "$cmd" | grep -Eq '(^|[;&|(`[:space:]])(rm|unlink|rmdir|shred)([[:space:]]|$)'; then
      root=$(abs_path "$CWD")
      for seg in $(printf '%s' "$cmd" | tr ';|&' '\n\n\n' | grep -E '(^|[[:space:]])(rm|unlink|rmdir|shred)([[:space:]]|$)' | sed -E 's/.*(^|[[:space:]])(rm|unlink|rmdir|shred)[[:space:]]+//'); do
        case "$seg" in -*) continue ;; esac
        case "$seg" in *'$'*|*'`'*) deny "rm with an unresolvable path $seg" ;; esac
        p=$(abs_path "$seg")
        case "$p" in "$root"|"$root"/*) ;; *) deny "rm outside project root: $seg" ;; esac
      done
    fi ;;
esac
exit 0
