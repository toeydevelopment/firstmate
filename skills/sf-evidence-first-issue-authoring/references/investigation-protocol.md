# Investigation Protocol

Use this protocol for both drafting and auditing issues. Adapt the depth to the risk:
a copy change needs less evidence than auth, billing, tenancy, migration, or data-loss
work.

## 1. Establish Scope and Authority

Capture:

- repository and relevant app/package/module;
- current worktree state and inspected commit SHA;
- default branch and remote freshness when available;
- user-provided symptom, screenshots/logs/request payloads, and environment;
- whether production/runtime access is authorized and read-only;
- explicit product decisions versus the AI's inferred preference.

Read the nearest `AGENTS.md`, contributor guide, architecture rules, issue forms, and
domain-specific docs. In a monorepo, repeat this check at the relevant subtree.

Do not use a dirty local change as proof of default-branch behavior. If the only
available checkout is dirty, identify which evidence comes from committed `HEAD` and
which may include local modifications.

## 2. Search Before Diagnosing

Check, when available:

- open and recently closed issues and pull requests;
- release notes or recent commits around the affected area;
- endpoint, route, UI label, error code, event, table/collection, and public contract;
- tests that document intended behavior;
- all callers and consumers of a symbol proposed for change;
- generated clients, schemas, migrations, background jobs, and cross-repo consumers.

Use repository graph/impact tools when configured. Otherwise use exact text search,
call-site tracing, compiler/type information, and focused tests. Report the fallback;
do not pretend semantic impact analysis occurred.

## 3. Trace the Complete User Flow

Follow the actual path that produces the symptom. Typical paths include:

```text
UI interaction -> client mapping/cache -> API contract -> handler/service
-> business rule -> repository/query -> stored state/external service
```

or:

```text
scheduler/event -> worker -> business rule -> mutation -> audit/outbox/notification
```

Inspect only the layers relevant to the behavior, but do not stop at the first matching
function. Verify tenant/authorization scope, soft deletion, status transitions,
pagination/aggregation boundaries, transactions, retries/idempotency, and audit/history
effects when applicable.

For a cross-repository request, verify both sides of the contract. If another repo is
not available, name that as unverified scope instead of guessing its state.

## 4. Build an Evidence Ledger

Keep a compact working ledger. Material claims in the final issue should be traceable
to it.

| Claim | Class | Evidence | Confidence / gap |
|---|---|---|---|
| The endpoint returns 403 for an unchanged value | Observed | sanitized request/response, alpha, timestamp | high |
| The permission helper treats any non-zero value as a change | Code-confirmed | `path/file.go:Lx-Ly` at SHA | high |
| Production records are affected | Hypothesis | same code is deployed, data not checked | needs runtime check |
| Existing values should remain editable | Decision | product owner statement or linked spec | approved |
| Compare stored and requested values | Proposal | derived from current flow | engineer must assess race/transaction behavior |

The issue body need not contain a large table when prose is clearer, but it must retain
the distinctions.

## 5. Decide Whether the Cause Is Proven

A root cause is proven only when the traced code/data path explains the observed
behavior and competing explanations have been ruled out to a reasonable level.

Use **suspected cause** when any link is missing, including:

- static code without evidence that the affected environment runs that revision;
- API evidence without the relevant stored state;
- an error message that can originate from multiple paths;
- a frontend symptom without the actual request/response;
- a database hypothesis without tenant, branch, status, or soft-delete scope;
- a proposed fix that would mask the symptom but does not explain it.

For a deterministic static defect, a focused existing test or small read-only
reproduction may establish the behavior. Do not modify product source merely to make an
issue appear verified.

## 6. Bound Impact Without Inflating It

State what is confirmed affected, plausibly affected, and checked unaffected. Do not
infer “all users,” “production,” “data loss,” “security,” or “critical” from code shape
alone.

For high-risk domains, include relevant checks:

- auth/RBAC: caller, target, tenant, escalation and lockout paths;
- money/stock: stored aggregate plus ledger/history and reversal paths;
- data migration: source/target counts, rollback/recovery, idempotency;
- background jobs: eligibility boundary, retries, concurrency, partial failure;
- search/list: filters, pagination, sorting, aggregation, encrypted fields;
- API changes: compatibility, generated clients, old/new consumer behavior.

## 7. Derive Constraints, Then Options

Extract facts that constrain a solution: public contracts, compatibility promises,
architectural boundaries, authoritative data source, transaction requirements,
performance limits, and repository rules.

Only then list possible approaches. For each non-trivial proposal, note the trade-off
or missing validation. Avoid arbitrary constants and exact file-level designs unless
evidence supports them. An implementation idea generated by AI is not a product
decision.

## 8. Verify Test and Delivery Instructions

Confirm test commands from repository files and CI configuration. Check that named
tests, packages, Make targets, scripts, migrations, labels, and deploy steps exist.

Separate:

- **Evidence run now** — command actually run and result;
- **Implementation self-test** — existing command the engineer should run;
- **Release verification** — environment check needed after merge/deploy.

Do not require a test layer the repository cannot support. When runtime reproduction is
not possible, specify the observable scenario the future regression test must prove.

## 9. Stop Conditions

Stop and downgrade readiness when:

- expected behavior needs a product/security/data-owner decision;
- required repository or environment is unavailable;
- runtime verification needs authority not granted;
- evidence contradicts the requested solution;
- multiple independent outcomes are bundled;
- the issue duplicates or has been superseded by current work.

State the smallest next check or decision that would unblock an implementation issue.
