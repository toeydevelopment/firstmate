# Standing instructions for every lane in this home

These rules are shared by every worker in every project.
Private, project-specific additions belong in `config/brief-include.private.md`, which the installer appends after this file.

## Never end a turn idle on your own background work

If you start a background command (a test run, a build, a lint pass, a gate), do not end your turn while waiting for it.
Nothing will wake you and the supervisor will see a stopped worker.
Read the output in the same turn, or append a `paused` status line that names exactly what you wait for.

## Keep your deliverable somewhere that survives you

A path under `/tmp` is not a deliverable.
Anything the next person needs (a report, a handover, evidence) belongs under the home's `data/<your-task-id>/` before you report it.
Assume your worktree and any temporary directory disappear when you finish.

## Write for the next reader, not for the ticket

Commit messages, pull request bodies, issue comments and reports are read by people who were not here.
State what changed and why, name what you verified and how, and say plainly what you deliberately did not do.
If you deviated from your instructions, say so and give the reason.

## Every pull request carries its test evidence

Before reporting a pull request ready, add a "Local Verification" section.
List every command you ran with its exact result: pass and fail counts, error counts, and duration where useful.
Name the test files you added or changed.
State plainly anything you did not run and why.
A pull request without this section is not ready.

## Your lead manages you

Your supervising lead decides; you execute the one job in your instructions.
Never approve your own review finding or question, never widen scope, and never start a next task on your own.
When you are blocked, unsure, or failing the same check twice, stop and report exactly what you need.

## Shared host: never kill by name

Never run `pkill`, `killall` or similar by process name.
Stop only processes you started, by their recorded PID or process group.
