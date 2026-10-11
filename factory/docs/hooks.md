# Guard hooks

`factory/hooks/sf-guard.sh` is a Claude Code `PreToolUse` hook that stops three mistakes before a worker makes them.
It follows the documented hook contract: the tool call arrives as JSON on stdin (`tool_name`, `tool_input`, `cwd`), and the hook blocks by exiting 2 with the reason on stderr.
Any other exit means no decision, so a missing `jq` or a malformed payload never blocks work.

## What it blocks

- Reading a secret file with the Read tool or a Bash reader such as `cat`, `grep` or `source`.
  Secret files are `.env`, `.env.*`, `*.pem`, `id_*`, `.credentials*`, `*credentials.json`, `.netrc`, and token files named `token`, `.token`, `*.token` or `token.json`.
  Names ending in `.example`, `.sample`, `.template` or `.pub` are allowed.
- Writing a literal secret with Write, Edit or MultiEdit: AWS access key ids, GitHub, Slack, Anthropic and OpenAI style tokens, and PEM private key headers.
- `rm`, `unlink`, `rmdir` or `shred` on a path outside the project root (the hook's `cwd`).
  A path built from a variable or command substitution is blocked because it cannot be checked.

The Bash checks are a heuristic over the command text, not a sandbox.
They catch the common accidents; they do not stop a determined bypass such as an encoded command.

## Exceptions for firstmate

- Anything under `$FM_HOME/state/` and `$FM_HOME/data/` is never blocked, so status files, steering inboxes, task tokens and reports stay readable.
- `gh auth` needs no exception: `gh auth token` and `~/.config/gh/hosts.yml` match no secret pattern.
- Firstmate scripts that source files such as `config/x-mode.env` do so inside the script, outside any tool call, so the hook never sees them.
- To allow more paths, set `SF_GUARD_ALLOW` to a colon-separated list of path prefixes in the worker's environment.

## Install

```sh
factory/bin/sf-hooks-install.sh <settings.json>            # dry run, prints the diff
factory/bin/sf-hooks-install.sh <settings.json> --apply    # backs up to <settings.json>.sf-bak, then writes
```

The installer never runs on its own and touches only the file you name, for example a project's `.claude/settings.json`.
It keeps existing settings and hooks, and running it again changes nothing.

## Tests

`bash factory/tests/sf-guard.test.sh` feeds sample hook JSON to the guard.
`bash factory/tests/sf-hooks-install.test.sh` runs the installer against temporary files.
