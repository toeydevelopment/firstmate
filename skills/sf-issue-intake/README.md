# sf-issue-intake

Verifies issues written by non-technical authors against the default-branch code, relates them to their parent epic, and returns a short report plus a visual HTML brief with one decision card per issue. It never implements, comments on, labels or edits issues.

## Install

With the Agent Skills installer:

```bash
npx skills add toeydevelopment/firstmate --skill sf-issue-intake
```

As a Claude Code plugin:

```text
/plugin marketplace add toeydevelopment/firstmate
/plugin install sf-issue-intake@toeydevelopment-firstmate
```

The skill itself is in [SKILL.md](SKILL.md).

It works best together with [sf-evidence-first-issue-authoring](../sf-evidence-first-issue-authoring/README.md), whose investigation protocol and audit rubric it reuses.
The brief's diagram style follows [diagram-design](https://github.com/cathrynlavery/diagram-design) by Cathryn Lavery (MIT).
The attribution stays in the generated page footer.

## License

MIT.
