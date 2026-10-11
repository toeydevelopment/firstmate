# Epic delivery

An epic ships as one pull request per repository.
`factory/bin/sf-epic-gate.sh` checks that rule before the epic pull request merges.
The gate only reads.
After a pass, firstmate merges with `bin/fm-pr-merge.sh`.

## The rule

- Each ticket of the epic is a pull request that targets the repository's `epic/<slug>` branch, never the default branch.
- Ticket pull requests merge into the epic branch as they finish.
- The epic branch then ships to the default branch as a single pull request, whose body closes every issue the epic covers.
- End-to-end tests pass on the exact commit that merges, not on an earlier one.

## What the gate checks

Run `sf-epic-gate.sh [--parent <issue>] [--config <path>] [--dispatch] <owner/repo> <epic-pr-url-or-number>`.
It prints a numbered PASS, FAIL or SKIP line per check and exits 1 when any check fails.

1. The head branch is `epic/*`.
2. The base branch is the repository's default branch.
   GitHub closes linked issues only when a pull request merges into the default branch, so an epic pull request aimed anywhere else leaves its issues open.
3. The epic pull request body has a `Closes`, `Fixes` or `Resolves` line for every issue that a pull request merged into the epic branch closes.
   Only same-repository issues count, and ticket pull requests that were closed without merging are ignored.
4. With `--parent`, the body also closes every same-repository child issue of that parent issue.
   Without `--parent` this check is skipped.
5. The E2E workflow named in the config has a completed, successful run on the epic pull request's head SHA.
   A success on any other commit does not count, so a push after the run sends the epic back to this check.

Exit codes: 0 all checks passed, 1 a check failed, 2 bad arguments, missing config or a GitHub read error.

## E2E dispatch

The gate never starts a workflow unless asked.
With `--dispatch`, and only when the head SHA has no run of the workflow at all, it runs `gh workflow run <workflow> --ref <epic branch>` and reports check 5 as failed until the run finishes.
Run the gate again after the workflow completes.
A head SHA whose runs all failed is reported, not re-dispatched, because re-running a failing suite should be a decision.

## Config

Copy `factory/config-templates/epic-delivery.json` to `config/epic-delivery.json` in the firstmate home, or pass `--config` or set `SF_EPIC_DELIVERY_CONFIG`.
`repos.<owner/repo>.e2eWorkflow` names the workflow file (or numeric workflow id) for that repository.
`default.e2eWorkflow` applies to repositories without their own entry.
The config belongs in the private home because workflow names can be team-specific.

## Ledger

`sf-epic-gate.sh --ledger [--parent <issue>] <owner/repo> <epic-pr>` prints the epic ledger from the same GitHub data.
It lists one row per ticket and pull request with the pull request's status (`merged`, `open` or `closed`), a `no PR` row for each child of `--parent` without a pull request, and a final row for the epic pull request.
Use it instead of keeping a hand-written ledger.

## Tests

`factory/tests/sf-epic-gate.test.sh` runs the gate against recorded JSON in `factory/tests/fixtures/epic-gate/` through a fake `gh`, with no network.
