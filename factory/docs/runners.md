# Runner operations and health sampler

The factory ships a generic runner skill and a read-only sampler for self-hosted GitHub Actions runners that live on a VM reached over ssh.
Both read one config file, so no host name, organization or path appears in a tracked file.

## Configure

1. Copy `factory/config-templates/runners.env` to `config/runners.env` in your firstmate home.
2. Replace every example value.
   The file is plain `KEY=value` lines and is sourced by bash, so keep values simple and free of spaces.
3. Keep the real file private: `config/` is gitignored and never committed.

`SF_RUNNERS_ENV` overrides the file location when you keep it elsewhere.

## The skill

`skills/sf-runner-ops/` explains how to check, explain and carefully change the runners.
It is read-only by default.
It keeps hard limits (no VM destroy, no restart while a job runs, no broad prune, no deregistering, no cap above `SF_RUNNER_MAX_CAP`) and requires an explicit yes for every state change.
Install it like any other public factory skill.

## The sampler

`factory/bin/sf-runner-sample.sh` makes one ssh call and reads disk use, tmpfs use, available memory, the busy-job count and the autoscaler's last skip reason.
It prints one wake line only when a threshold in `runners.env` is crossed, or when the machine cannot be reached, and prints nothing otherwise.
After a wake line it stays quiet for `SF_RUNNER_BACKOFF_SECONDS`, using a marker file in the home's `state/`.
It never changes caps, restarts anything or cleans anything.
`factory/bin/sf-runner-sample.sh --print` shows every sampled value and ignores the back-off, which is the quickest way to test a new `runners.env`.

## Register it as a firstmate custom check

A custom check is an executable `state/<id>.check.sh` whose standard output becomes a wake message.
Registration binds the exact file bytes with `bin/fm-check-register.sh`, so re-register after every edit.
From your firstmate home:

```bash
cat > state/runner-health.check.sh <<'SCRIPT'
#!/usr/bin/env bash
exec /path/to/firstmate/factory/bin/sf-runner-sample.sh
SCRIPT
chmod 700 state/runner-health.check.sh
bin/fm-check-register.sh runner-health
```

Use the absolute path of your checkout in the `exec` line.
Retire the check with `bin/fm-check-unregister.sh runner-health`.
Run `bin/fm-check-register.sh` by hand, not from the check itself, because registration is an intentional act.

## Test

```bash
bash factory/tests/sf-runner-sample.test.sh
```

The test stubs `ssh`, so it needs no runner machine.
