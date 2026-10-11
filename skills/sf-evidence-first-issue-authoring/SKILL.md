---
name: sf-evidence-first-issue-authoring
description: >
  Investigate a repository and draft or audit evidence-grounded engineering
  issues. Use when a PM, product owner, or engineer asks AI to turn a bug,
  feature request, runtime observation, or proposed solution into a GitHub or
  GitLab issue without implementing it. Routes unverified work to an
  investigation or product-decision issue instead of inventing an
  implementation-ready ticket.
---

# Evidence-First Issue Authoring

Turn product input into an issue an engineer can trust. Repository exploration is
part of the work; source changes are not.

## Boundaries

- Work read-only in product repositories. Do not implement the fix, modify source,
  create branches, or open pull requests while using this skill.
- Drafting an issue does not authorize publishing it. Create or edit an issue only
  when the user explicitly asks for that external mutation.
- Preserve dirty worktrees. Do not switch branches, reset changes, or treat local
  modifications as the default branch.
- Follow repository instructions, security boundaries, and production-access rules.
- Do not expose secrets, tokens, personal data, patient/customer details, or
  unnecessary live record identifiers in an issue.

## Choose the Mode

1. **Draft** — investigate a reported problem or feature request and write the
   appropriate issue type.
2. **Audit** — verify an existing AI-written issue against the current repository,
   identify unsupported or contradicted claims, and produce a corrected draft when
   useful.
3. **Publish** — run Draft or Audit first, then create/update the issue only if the
   user requested publication and the destination repository is unambiguous.

For Draft and Audit, read
[references/investigation-protocol.md](references/investigation-protocol.md). For
the issue body, read [references/issue-templates.md](references/issue-templates.md).
For Audit, also read [references/audit-rubric.md](references/audit-rubric.md).

## Core Workflow

### 1. Establish the evidence snapshot

Record the repository, inspected revision or commit SHA, worktree state, relevant
environment, and observation time. Read the repository's agent/contributor
instructions and existing issue template before making claims.

When remote access is available, check the current default branch and search open and
recently closed issues/PRs for duplicates or superseding work. If remote state was not
checked, say so.

### 2. Separate claims by confidence

Classify every material statement using these meanings:

- **Observed** — directly reproduced or present in supplied runtime evidence.
- **Code-confirmed** — current code deterministically establishes the behavior.
- **Decision** — desired product behavior explicitly supplied by an authorized
  decision-maker or an authoritative product document.
- **Hypothesis** — plausible but not proven; include the disconfirming check.
- **Proposal** — one possible implementation, not a requirement unless the decision
  and repository constraints make it binding.

Never promote a hypothesis to “root cause,” a proposal to “required change,” or a
code reading to “production is affected.” Do not say a command, test, endpoint, or
database check was run unless it actually was.

### 3. Assign the readiness verdict

Use exactly one verdict:

- **READY — implementation issue**: the behavior or gap is established, expected
  behavior is decided, scope is bounded, repository references are valid, acceptance
  criteria are behavioral and testable, and verification commands are known to exist.
- **NEEDS INVESTIGATION**: reproduction, affected scope, or cause is too uncertain.
  Write an investigation issue with exit criteria, not a speculative fix ticket.
- **NEEDS PRODUCT DECISION**: code can be understood, but correct behavior or a
  trade-off is undecided. Write a decision issue with concrete options and impact.
- **DUPLICATE / SUPERSEDED**: existing work already owns the outcome. Link it and
  explain the overlap instead of creating another ticket.

A user may explicitly choose to publish an investigation or decision issue. “Not
implementation-ready” does not mean “no issue”; it means the issue type must be honest.

### 4. Write behavior before design

Acceptance criteria describe externally observable behavior, invariants, failure
handling, tenant/security boundaries, and important regressions. Put file names,
symbols, schema fields, library choices, query shapes, magic numbers, and migration
mechanics in **Implementation constraints** or **Possible approach**, unless an
approved contract or repository rule makes them mandatory.

Prefer:

> Given an appointment linked to a patient with a nickname, searching by a nickname
> substring returns that appointment without changing existing name search.

Over:

> Add protobuf field 28, copy helper X, and cap the lookup at 2,000 rows.

The first states the product outcome. The second is an engineering proposal that must
be independently validated.

### 5. Keep one issue responsible for one outcome

Do not bundle adjacent bugs, cleanup, migrations, frontend follow-ups, and policy
questions merely because they were discovered together. Link follow-ups. Split work
when it has a different user outcome, owner, readiness verdict, release risk, or
verification path.

### 6. Verify the verification plan

Use commands and targets that exist in the inspected repository. Prefer focused tests
that prove acceptance criteria, plus the repository's required broader checks. Mark
commands not run as **recommended**, not **passing**. Never invent `make`, package,
lint, migration, or deploy commands from convention.

## Required Response

Before publishing or handing off a draft, provide:

1. the readiness verdict and one-sentence reason;
2. the issue title and body appropriate to that verdict;
3. unresolved questions and unverified scope, if any;
4. the evidence snapshot used;
5. for Audit mode, the blocking findings before the revised issue.

If the user asked to publish, confirm the final repository, issue URL/number, and any
labels actually applied. Do not claim labels, assignees, milestones, or project state
that the destination does not have.

## Final Quality Gate

Do not call an issue implementation-ready unless all are true:

- Every current-state and root-cause claim has cited evidence at the inspected
  revision.
- Runtime claims identify their environment and source, or are explicitly unverified.
- Desired behavior is a product decision, not an AI preference.
- Acceptance criteria can be verified without following the suggested implementation.
- Scope, non-goals, edge cases, and security/data boundaries are explicit.
- Referenced files, symbols, issue links, and commands were checked.
- No unrelated finding or sensitive live data leaked into the body.
- The proposed title and labels match what is known, without invented urgency.

When any item fails, downgrade the verdict and say exactly what evidence or decision
would make it ready.
