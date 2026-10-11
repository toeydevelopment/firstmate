# Card and Report Format

Shapes for the decision card, the markdown report, and the decide block. Keep
every field short. If a field needs more than two lines, the issue probably needs
a **split** or **clarify first** recommendation instead.

## Decision card

```
#<n> <title>                          [recommendation]
Parent: <epic/spec link, or "none found (checked: sub-issue link, milestone, labels, body links, referenced issues)">
Problem:   <one line>
Affected:  <roles or people>
Done when: <observable outcome, plain words>
Claims:    <C confirmed · W wrong · S stale · U unverified>
           - <the one or two claims that matter, with path:line or the reason unverified>
Size/risk: <S|M|L> · <low|medium|high>: <one reason>
Order:     <only when needed>
Ask the author:
  Q1. <plain question>  [suggested default: ...]
  Q2. ...
Why <recommendation>: <one sentence>
```

### Recommendation meanings

| Recommendation | Use when |
|---|---|
| **act** | Claims hold, outcome is decided, scope is one piece of work. |
| **clarify first** | The problem is real but expected behavior, scope, or a fact is missing. List the questions. |
| **split** | It bundles pieces with different outcome, owner, risk, or verification. Name the pieces and the order. |
| **close** | Already works, duplicate, superseded, or wrong. Cite the evidence or the owning issue. |

Pick one. If two seem to apply, lead with the one that blocks the other
(usually split, then clarify the pieces).

### Size and risk

- **S**: one place, additive or small guard. **M**: a few places or a contract
  change with tests. **L**: several areas, or a migration, or two outcomes in one.
- **Risk** rises with: money, legal documents, auth or permissions, customer
  notifications, data migration, shared contracts with other teams, and anything
  hard to undo. Say which one drives the rating. Data already damaged by a bug is
  not repaired by the fix: note it.
- Size is an estimate from reading the code, not a commitment.

### Writing questions for the author

- Plain words. No file names, symbols, or protocol terms.
- Describe the situation the person knows (a screen, a customer, a printed
  receipt), then ask for the choice.
- Offer a suggested default when the code or a prior decision points to one, so
  the reader can answer "yes" instead of writing.
- Ask about facts only the author knows (policy, law, who is affected, how often).
  Do not ask them to approve a design.
- When the issue touches a document with legal or money meaning (receipt,
  invoice, refund, balance), always ask: is a legal layout required, and may an
  edit after the document was given to a customer change what a reprint shows.
  The author knows; the code cannot say.
- Drop any question whose answer would not change what gets built.

## Markdown report

```
# Issue intake: <repo> <#a, #b, ...>

Scope: knowledge only. No code changed, no issue commented, labeled, or edited.
Snapshot: <repo> <branch> @ <sha>, <date>. Not checked: <list>.
Visual brief: <path to html>

## At a glance
| Issue | Recommendation | Size/risk | Claims C/W/S/U | Parent |
|---|---|---|---|---|

## Parent epic
<one line per issue or group; "none found" is explicit>

## How they relate
<groups, dependencies, overlap, suggested order>

## Cards
<one card per issue, in the shape above>

## Decide and discuss
<numbered block>
```

Keep the overview table at the top: the reader may stop there.

## Decide and discuss block

Numbered items the reader answers with a number and a word.

Order of items:

1. Sequence and grouping (one item).
2. Recommendations that need a yes/no (split? close? ship alone first?).
3. Author questions, grouped by issue, each with its suggested default.
4. Anything blocked on a fact nobody on the thread has (for example a read-only
   data check that needs production access).

Rules:

- Mark who answers each item: **lead** (order, ownership, split, linking an
  epic) or **author** (policy and facts). Put lead items first. Suggested
  defaults for author questions come from what the code does today, and say so.
- Every item is answerable in one word or letter.
- Show the suggested default so "go with defaults" is a valid reply.
- Number once, continuously across issues, so "7 no" is unambiguous.
- End with: `Reply like "1 yes, 2 default, 3 no, 4 let's talk".` The reader can
  then continue the discussion about any number.
- Do not repeat card text in the block; refer to the card by issue number.

## Sensitive data

Use roles and counts, not names. Replace customer, patient, or account
identifiers with a neutral label. Do not paste secrets that appear in an issue;
say that the issue contains one and where, so it can be rotated.
