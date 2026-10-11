# Issue Templates

Choose the template that matches the readiness verdict. Remove unused optional
sections; never fill gaps with plausible-sounding details.

## Implementation Issue

Use only for `READY — implementation issue`.

```markdown
## Readiness

**READY — implementation issue**

- Evidence base: `<repo>` at `<commit SHA>`
- Runtime evidence: `<environment and timestamp, or “not required / unavailable”>`
- Product decision: `<source of expected behavior>`

## Problem

<Observed current behavior and user/business impact. Keep inference out.>

## Reproduction / current behavior

1. <Minimal deterministic setup or precondition>
2. <Action>
3. <Actual result, sanitized>

If runtime reproduction was unavailable, replace this section with **Static proof** and
explain why the current code deterministically establishes the defect.

## Expected behavior

<Outcome approved by product/security/data owner.>

## Repository evidence

- `<path>:<lines>` at `<SHA>` — <what this proves>
- `<path>:<lines>` at `<SHA>` — <what this proves>
- `<test/contract/issue link>` — <why it is authoritative>

## Scope

### In scope

- <one coherent outcome>

### Out of scope / follow-ups

- <adjacent finding and link, if any>

## Acceptance criteria

- Given <state>, when <action>, then <observable result>.
- Given <edge/failure state>, when <action>, then <observable safe result>.
- <Existing behavior that must not regress>.
- <Tenant/security/audit/compatibility invariant when relevant>.

## Verification

```sh
<focused existing command>
<required repository check>
```

- Release check: <runtime validation if relevant>
- Commands run during investigation: <result, or “none”>

## Implementation constraints

- <binding contract, architecture, transaction, migration, or compatibility fact>

## Possible approach (non-binding)

<Include only when it materially helps. State alternatives/trade-offs and what the
implementer must validate.>

## Risks / open questions

- <Known residual uncertainty, or “None blocking implementation”>
```

Do not turn the Definition of Done into process boilerplate such as “clean commit” or
“comment files changed” unless the repository explicitly requires it. Completion is
the acceptance criteria plus verified repository checks.

## Investigation Issue

Use for `NEEDS INVESTIGATION`. Its deliverable is evidence or a decision-ready
diagnosis, not code.

```markdown
## Readiness

**NEEDS INVESTIGATION** — <what is not known>

- Evidence base: `<repo>` at `<commit SHA>`
- Reported environment/time: `<source>`

## Reported symptom

<What was observed, by whom/source, with sensitive data removed.>

## What is confirmed

- <Observed or code-confirmed fact with reference>

## Hypotheses to test

1. <Hypothesis> — confirm with <check>; disprove with <check>.
2. <Hypothesis> — confirm/disprove path.

## Investigation scope

- <Read-only checks, affected layers/repos, data scope>

## Exit criteria

- Reproduction is confirmed or ruled out at a named revision/environment.
- Affected scope is bounded.
- Root cause is proven or remaining hypotheses are explicitly ranked.
- Required product/security/data decision is identified.
- A separate implementation issue can be written with behavioral acceptance criteria.

## Non-goals

- Implementing or deploying a fix in this issue.

## Evidence to attach

- <sanitized request/response, test output, query counts, logs, or file references>
```

## Product Decision Issue

Use for `NEEDS PRODUCT DECISION`. Do not hide a policy choice inside technical
acceptance criteria.

```markdown
## Readiness

**NEEDS PRODUCT DECISION** — <decision that blocks implementation>

## User impact / scenario

<Concrete current behavior and why the decision matters.>

## Confirmed constraints

- <contract/data/security/compatibility fact with evidence>

## Options

### Option A — <behavior>

- User outcome: <...>
- Engineering/data risk: <...>
- Trade-off: <...>

### Option B — <behavior>

- User outcome: <...>
- Engineering/data risk: <...>
- Trade-off: <...>

## Decision required

- <specific question answerable by product/security/data owner>
- Owner: <known owner or “unassigned”>

## After the decision

- Record the chosen behavior and rationale.
- Create/update the implementation issue with behavioral acceptance criteria.
```

## Duplicate / Superseded Note

Do not create another issue by default. Report:

- existing issue/PR link;
- exact overlapping outcome;
- any uncovered behavior that warrants a separate issue;
- whether the existing work is open, merged, released, or merely proposed.
