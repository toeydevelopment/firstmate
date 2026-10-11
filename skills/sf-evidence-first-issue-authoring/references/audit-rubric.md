# Audit Rubric for AI-Written Issues

Audit the issue as an engineer would review a risky change request. Verify claims
against the inspected revision; do not grade writing style in place of correctness.

## Verdicts

- **Ready** — safe to hand to an implementer after minor editorial cleanup at most.
- **Revise** — core problem is valid, but blocking claims, scope, criteria, or
  verification instructions must change.
- **Investigation required** — evidence is insufficient to request a fix.
- **Product decision required** — expected behavior or trade-off is not authorized.
- **Duplicate / superseded** — existing work owns the same outcome.

## Blocking Findings

Treat these as blockers:

- claimed reproduction, test, data check, or environment state was not actually
  verified;
- file, symbol, route, field, line, or commit reference is wrong or stale enough to
  change the conclusion;
- “root cause” is only a hypothesis or ignores another reachable path;
- proposed design violates repository architecture, contracts, security, tenancy,
  encryption, transaction, migration, or compatibility rules;
- desired behavior is an AI preference rather than a recorded product/security/data
  decision;
- acceptance criteria require a particular implementation but do not define the user
  outcome;
- the issue combines independent outcomes with different owners or readiness;
- self-test, build, migration, label, or deployment instructions do not exist;
- sensitive production/customer data is unnecessary or insufficiently redacted;
- another active issue or merged change already owns or changes the conclusion.

## Risk Findings

Flag these even when not blocking:

- exact helper/file/query/schema suggestions presented as mandatory without evidence;
- arbitrary caps, timeouts, field numbers, indexes, or performance claims;
- missing negative cases, authorization scope, tenant isolation, soft-delete handling,
  reversal/rollback, idempotency, or audit behavior where relevant;
- runtime impact inferred solely from static code;
- issue references “main” without a commit SHA while code is changing rapidly;
- adjacent findings included as notes that are likely to expand implementation scope;
- frontend/backend contract claims checked in only one repository;
- severity or urgency unsupported by bounded impact.

## Claim Audit

For each material claim, assign one status:

- **Verified** — supported by current evidence.
- **Contradicted** — repository/runtime evidence shows otherwise.
- **Unsupported** — may be true, but evidence is missing.
- **Stale** — true at the cited revision but not current.
- **Decision** — authorized desired behavior, not a factual repository claim.
- **Proposal** — optional design requiring engineering validation.

Use a compact findings table:

| Severity | Claim | Status | Evidence | Required correction |
|---|---|---|---|---|
| Blocker | `<claim>` | Unsupported | `<path/command/runtime source>` | `<rewrite or next check>` |

Lead with blockers. Do not bury them under a rewritten issue.

## PM/Engineer Responsibility Check

The issue should let a non-engineering PM verify:

- the user problem and impact;
- the intended behavior;
- example scenarios and acceptance criteria;
- scope and priority.

It should let an engineer verify:

- root-cause evidence and blast radius;
- architectural and data constraints;
- proposed approach and trade-offs;
- test, migration, release, and rollback requirements.

If the issue asks the PM to approve an internal implementation detail they cannot
meaningfully evaluate, move it to a non-binding proposal. If it asks the engineer to
invent product behavior, downgrade to a product-decision issue.

## Audit Output

Return, in order:

1. verdict and one-sentence rationale;
2. blocking findings table;
3. risk findings;
4. verified facts worth preserving;
5. missing evidence or product decisions;
6. corrected issue draft, when enough information exists;
7. exact checks required before publication or implementation.

Do not update or close the original issue unless the user explicitly asks.
