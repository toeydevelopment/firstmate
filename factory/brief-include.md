# Standing instructions for every lane in this home

These rules are shared by every worker in every project.
Private, project-specific additions belong in `config/brief-include.private.md`, which the installer appends after this file.

## Never end a turn idle on your own background work

If you start a background command (a test run, a build, a lint pass, a gate), do not end your turn while waiting for it.
Nothing will wake you and the supervisor will see a stopped worker.
Read the output in the same turn, or append a `paused` status line that names exactly what you wait for.

## Keep your deliverable somewhere that survives you

A path under `/tmp` or `/var/folders` is not a deliverable.
Anything the next person needs (a report, a handover, evidence) belongs under the home's `data/<your-task-id>/` before you report it.
Assume your worktree and any temporary directory disappear when you finish.

## Hosted CI is a signal, not a formality

Local verification is always required: run the repository's own commands in your worktree and record the exact commands, commit SHAs and results in the pull request.
Also report the hosted check results for your pull request head.
A red hosted check is a real signal: investigate it and fix it or explain it, and never dismiss it as unavailable CI.
A hosted check that was cancelled, or never started because of runner capacity, may be re-run once; say so in the pull request.

## Write for the next reader, not for the ticket

Commit messages, pull request bodies, issue comments and reports are read by people who were not here.
State what changed and why, name what you verified and how, and say plainly what you deliberately did not do.
If you deviated from your instructions, say so and give the reason.

## Every pull request carries its test evidence

Before reporting a pull request ready, add a "Local Verification" section.
List every command you ran with its exact result: pass and fail counts, error counts, and duration where useful.
Name the test files you added or changed.
State plainly anything you did not run and why.
For user-interface changes, include real-browser evidence of the changed screens, such as screenshots or a recorded journey.
Reviewers must see screenshots in the pull request itself, so embed them in the description rather than naming files, and keep existing embeds intact when you edit it.
If your delivery path cannot embed images, say so plainly in the pull request and in your done report.
A pull request without this section is not ready.

## Pull request descriptions

Read the repository's `.github/pull_request_template.md` before you open or edit a pull request.
Fill every `## ` heading it lists, in its order, in one edit, because a workflow check that rejects the body reports one missing section at a time.
When the repository has no template, use these headings:

```markdown
## Summary
<diagram, pseudocode, call tree, or diff-sketch>

## Evidence
- **Before:** <output or failing test>  **After:** <output or passing test>

## Merge Danger
**Door:** <one-way, two-way or mixed>
**Blast Radius:** <one word> - <what can go wrong and how bad>
```

Mark a change one-way when it cannot be undone by reverting the pull request, such as a database migration, an encryption schema change, deploy or runtime configuration, payments, customer notifications, or auth behaviour.
Your home may list further one-way doors in its private additions below.

## Tests

Write tests through public interfaces.
Do not write tests that only restate constants, read source files as text, or mock away a dependency's real failure modes.

## Your lead manages you

Your supervising lead decides; you execute the one job in your instructions.
Never approve your own review finding or question, never widen scope, and never start a next task on your own.
When you are blocked, unsure, or failing the same check twice, stop and report exactly what you need.

## Keep the feedback loop short

Do not re-verify what the pipeline or CI already proved; run the narrowest check that answers the question.
Do not repeat an optional evidence probe after the first good result; record it once.
If the same step fails twice, stop and report it instead of trying a third variant.

## Repository workflow profile

If the repository has `docs/agents/workflow.md`, read it first and use its `quick-check`, `affected-check` and `delivery-check` commands.
Report `incomplete` or `NOT RUN` honestly, and never write `pass` for a skipped lane.
A task whose delivery path is no-mistakes does not run a separate review of its own.

## After your implementation commit, keep going

When your delivery path is no-mistakes, committing is not the end.
Right after the implementation commit, start the pipeline yourself with `no-mistakes axi run` and drive it to a pull request with green CI.
Do not report `done` and do not exit before the pull request exists.

## Review base for non-default-branch work

When the task's base branch is not the default branch, the reviewer can compare against the wrong branch and report findings about files outside your diff.
`factory/bin/sf-review-base.sh` always passes the task's base branch and scope sentence when it starts validation, so use it instead of calling `no-mistakes axi run` by hand.
`factory/bin/sf-review-scope-check.sh` lists the findings that cite files outside `git diff origin/<base>...HEAD`, so you can raise them as one decision for your lead.
Never edit files outside your own diff to satisfy such a finding.
After the pipeline's document step, run `git diff --stat origin/<base>...HEAD` and restore any file the document step rewrote that your change does not need documented.

## Findings you can decide yourself

These answers are already given, so respond through the gate right away instead of stopping for your lead:

- A finding about the pull request description only (missing or wrong section, door, approver, provenance table): fix the description and rerun only the affected check.
- A test-only change that makes a racy or flaky test deterministic and is needed for this pull request's CI to pass is in scope: keep it and say why under scope and limitations.
- A CI job cancelled without a verdict, or one that failed on runner capacity: rerun it once with `gh run rerun <run-id> --failed`.
- A CI failure that also fails on the base branch without your change is not yours: do not fix it in this pull request, record the evidence, and report `paused` while you wait for the base-branch fix.
- If `gh-axi` does not work in your worktree, use plain `gh` for the same action.

Still stop for your lead on anything that widens scope, changes product behaviour beyond the instructions, or is destructive.

## Shared host: never kill by name

Never run `pkill`, `killall` or similar by process name.
Stop only processes you started, by their recorded PID or process group.
