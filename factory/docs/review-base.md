# Review base guard

When a task targets an integration branch (for example `epic/<slug>` or `develop`) instead of the repository default branch, the no-mistakes review step can still diff against the default branch.
The reviewer then reports files that earlier tickets already merged into the integration branch as out of scope for the current change.
In this fleet 34 of 94 recent PRs targeted an `epic/*` branch and were exposed, and one run raised 10 false out-of-scope findings.

This overlay adds two small scripts and no change to no-mistakes:

- `factory/bin/sf-review-base.sh` prints the exact invocation a worker should use.
- `factory/bin/sf-review-scope-check.sh` lists findings that cite files outside the task's diff.

## What no-mistakes supports

Checked against no-mistakes v1.84.0 (`no-mistakes --help`, `no-mistakes axi --help`, `no-mistakes axi run --help`):

- `no-mistakes axi run --base-branch <branch>` is the only per-run way to pass a base.
  Its help says the base is "persisted on the run for rebase, PR, and CI steps" and that it overrides `pr.base_branch` in repo config.
  The help does not list the review step, and the observed runs show the review step still compared against the default branch.
- `pr.base_branch` in the repository's no-mistakes config is a standing setting for every run in that repository.
  It is tracked project configuration, so it is not a per-task answer and this overlay does not edit it.
- There is no environment variable or git config that sets the review diff base.

So no-mistakes has no supported way to make the review step use the task base.
The closest supported approach is the combination below, and it reduces the problem rather than removing it:

1. Pass `--base-branch <base>` on every run, so the rebase, PR and CI steps use the right base.
2. End the `--intent` text with the scope sentence, so the reviewer is told the real boundary in words.
3. After the review step, run the scope checker and dismiss what it lists in one step.

## Using the scripts

`sf-review-base.sh <task-id>` reads `base_branch=` from `$FM_HOME/state/<task-id>.meta`.
If the meta has none, `--pr <number-or-url>` (with optional `--repo owner/name`) reads the PR base through `gh`.
If neither gives a base, the task targets the default branch and the plain command is printed without a scope sentence.

```text
$ FM_HOME=/path/to/home factory/bin/sf-review-base.sh my-task --intent "Add the widget."
base: develop
scope: Review scope: only the changes in git diff origin/develop...HEAD; files outside that diff are not part of this task.
command: no-mistakes axi run --base-branch develop --intent Add\ the\ widget.\ Review\ scope:\ ...
```

The `command:` line is shell-quoted and can be pasted or `eval`ed as is.
Without `--intent` it carries the placeholder `<goal>`, which the worker replaces with the goal behind the change.

After the review step, save the findings text to a file and run, from the task worktree:

```text
factory/bin/sf-review-scope-check.sh findings.txt origin/develop
OUT-OF-DIFF 2 docs/other-ticket.md
OUT-OF-DIFF 3 src/shared/util.sh
```

Each line is a findings-file line number and a file that exists in the repository but is not in `git diff --name-only origin/develop...HEAD`.
The exit status is 1 when anything is listed, 0 when nothing is, and 2 for a usage or git error.
Paths in free text that do not exist in HEAD or the base are ignored, so versions and URLs do not produce noise.
A finding that cites both an in-diff and an out-of-diff file still lists the out-of-diff file; read it before dismissing it.
Never edit a file outside your own diff to satisfy such a finding.

Tests: `bash factory/tests/sf-review-base.test.sh`.

## Draft upstream issue

Status: not filed.
The no-mistakes repository (https://github.com/kunchenguid/no-mistakes) is public and accepts issues, but it already tracks this exact defect as https://github.com/kunchenguid/no-mistakes/issues/553 ("Review diffs against main instead of the PR base, causing false scope findings on stacked PRs", open, `ready-for-pr`).
Filing a second issue would duplicate it, so the text below is kept as the evidence to add to that thread if the maintainers want it.

Title: Review step diffs against the default branch even when the run has a `--base-branch`

Body:

> **Summary**
> With `no-mistakes axi run --base-branch epic/foo`, the run records the base for the rebase, PR and CI steps, but the review step still reviews `merge-base(HEAD, origin/<default>)..HEAD`.
> For work on an integration branch, that range includes every change already merged into the integration branch, so the reviewer reports those files as out of scope for the current change.
>
> **Evidence**
> - `no-mistakes axi run --help` (v1.84.0): `--base-branch` is "persisted on the run for rebase, PR, and CI steps"; it does not mention review.
> - In one fleet, 34 of 94 PRs opened in a day targeted an `epic/*` branch.
> - One run on such a branch raised 10 "out of scope" findings, every one about a ticket already merged into the epic branch. The files were all absent from `git diff origin/epic/foo...HEAD`.
> - Putting the scope in the `--intent` text does not reliably stop it. Callers end up dismissing each finding by hand.
>
> **Expected**
> The review range, and the intent-matching range, should start from the run's persisted base when one is set (and the existing PR's base when known), not only from the default branch.
>
> **Related**
> #553 describes the same behaviour for stacked PRs, and #580 / #886 proposed a configured base.
