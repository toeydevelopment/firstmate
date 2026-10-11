# Board projection

`factory/bin/sf-board-sync.sh` copies firstmate task state onto a GitHub Project board, so nobody updates the board by hand.
The backlog stays the source of truth and the board is a read-only projection of it.

## Setup

1. Copy `factory/config-templates/boards.json` to `config/boards.json` in the home that runs the sync.
   That file is private and gitignored, so it holds your real owner and project numbers.
2. Set `owner`, `tracker.number` and, for the optional second board, `ready_to_try.number`.
3. Make the field and option names match your boards exactly.
   The tracker needs a single-select `Status` field with the four options under `tracker.status`.
   `tracker.update_field` is an optional text field that receives the PR URL.
4. Run `factory/bin/sf-board-sync.sh` for a dry run, then `factory/bin/sf-board-sync.sh --apply`.

The script's header comment owns the exact options, environment variables and exit codes.

## What moves

| Task state | Board status |
|---|---|
| In flight | `in_progress` |
| In flight with a PR recorded in `state/<id>.meta` or the task links | `in_review` |
| Held for the captain | `waiting_on_captain` |
| Done, which is where the task lands after its PR merged and was cleaned up | `done` |

A queued task that is not held has not started and gets no card.
A done task that never had a card is not backfilled.
Each task gets one draft card titled `<task id>: <title>`.

## The "To try" board

When a user-visible task is done, write `data/<task id>/to-try.txt`.
Line 1 is the Where-to-try value, such as `Dev`, and an empty line falls back to `ready_to_try.where_default`.
Line 2 is an optional one-line summary of what changed.
On the next sync the task's PR is added to the ready-to-try board with status `ready_to_try.status_option` and those two fields.
Without a recorded PR no card is filed.
Each task is filed once.

## Rate limits and idempotence

The script keeps `state/board-cache/boards.json` with the project and field ids and the last state it pushed for each task.
A task whose state and PR are unchanged costs no API call, and a run with nothing to do calls nothing, not even the rate-limit check.
Before writing it reads the GraphQL budget and stops with exit 75 below `limits.min_graphql_remaining`.
It also stops with 75 after `limits.max_calls` calls, or when gh reports a rate limit.
The cache is saved after every successful call, so the next run resumes with only the remaining changes.
If you rename a board field or option, run with `--refresh` to refetch the ids.

## Running it

Run it from a heartbeat or a process-event watch, whichever your home already uses, rather than from a tight loop.
The script never reads the whole board, so cost scales with the number of changes.

## Tests

`bash factory/tests/sf-board-sync.test.sh` replays recorded gh output from `factory/tests/fixtures/board-sync/` through a fake gh and needs no network.
