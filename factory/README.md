# Software Factory overlay

This folder turns a firstmate fork into a deterministic software factory that any team can use on any project.
It is an overlay: everything the factory adds lives in new files, so upstream firstmate updates keep merging without conflicts.

## The add-only rule

A change on this fork may touch only these paths:

- `factory/`
- `skills/sf-*`
- `.claude-plugin/`
- `.github/workflows/sf-*`
- `docs/documentation-audiences.json`, only to add one sorted entry per new tracked `.md`, `.mdx`, `.rst` or `.txt` file

Never edit, rename or delete a file that exists upstream.
`factory/tests/sf-layout.test.sh` enforces this by diffing the branch against `upstream/main` and failing on any other path.
Nothing from `config/`, `data/`, `state/` or `projects/` is ever committed, because the fork is public.
Put example values in `factory/config-templates/` and keep real values in the gitignored `config/` of each home.

## Layout

```text
factory/
  README.md  VERSION
  bin/sf-install.sh          compose config/brief-include.md for one home
  bin/sf-sync-upstream.sh    merge upstream into the fork, then rerun the checks
  bin/sf-runner-sample.sh    read-only runner health sampler (custom check)
  bin/sf-board-sync.sh       project task state onto GitHub Project boards
  bin/sf-hooks-install.sh    merge the guard hook into a settings.json (dry run by default)
  hooks/sf-guard.sh          PreToolUse guard hook, see docs/hooks.md
  brief-include.md           shared standing rules for every worker
  config-templates/          example config files (boards.json)
  docs/boards.md             board projection setup and rules
  docs/fork-remotes.md       one-time remote and branch-protection setup
  docs/runners.md            runner skill config and health sampler check
  docs/hooks.md              what the guard hook blocks and its exceptions
  tests/                     plain-bash tests, run by the overlay workflow
skills/sf-<name>/            public skills installable into any project
.claude-plugin/              plugin marketplace entry (added by later tasks)
.github/workflows/sf-overlay-check.yml
```

## Install for a new user

1. Clone the fork: `git clone https://github.com/toeydevelopment/firstmate`.
2. Set the remotes once with the commands in [`docs/fork-remotes.md`](docs/fork-remotes.md).
3. Run `factory/bin/sf-install.sh --dry-run`, then `factory/bin/sf-install.sh`.
   It writes only `config/brief-include.md` under the active home.
   Put project-specific or private rules in `config/brief-include.private.md` first; the installer appends that file after the shared rules.
4. Run the installer once for every secondmate home, because secondmates do not inherit `brief-include.md`: `FM_HOME=<secondmate home> factory/bin/sf-install.sh`.
5. Work on any project as usual.
   Workers launched from this home now receive the factory rules in their instructions.

## Stay current with upstream

Run `factory/bin/sf-sync-upstream.sh` from a clean checkout.
It merges `upstream/main` (never a rebase, never a force), reruns `bin/fm-doc-audience-check.sh` and the tests in `factory/tests/`, and leaves the push to you.
Push the result without `--force`, so every home can keep fast-forwarding from the fork.

## Epic delivery

`factory/bin/sf-epic-gate.sh` checks an epic pull request before it merges and prints the epic ledger.
See [`docs/epic-delivery.md`](docs/epic-delivery.md).
