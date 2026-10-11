---
name: sf-runner-ops
description: Check, explain, and safely change self-hosted GitHub Actions runners that run on a VM you reach over ssh. Use when asked about "the runners", "self-hosted runner", "CI runner", jobs stuck in "Queued" or "Waiting for a runner", runner count or scaling caps, the runner VM's memory, disk or CPU, runner cleanup, or restarting runners after a reboot. All host values come from one runners.env file.
---

# sf-runner-ops

Operate self-hosted GitHub Actions runners that live on a VM.
The reader may be a small, cheap model, so this file gives exact commands and hard limits.
Read-only checks are always fine.
Anything that changes state needs the user's clear "yes" for that exact change first.

## Load the config first

Every host-specific value comes from one file, `runners.env`.
Look for it at `$SF_RUNNERS_ENV`, then `$FM_HOME/config/runners.env`.
If it is missing, tell the user to copy `factory/config-templates/runners.env` there and fill it in, then stop.
Load it in the shell before any command below:

```bash
set -a; . "${SF_RUNNERS_ENV:-$FM_HOME/config/runners.env}"; set +a
```

| Variable | Meaning |
|---|---|
| `SF_RUNNER_SSH` | ssh alias or `user@host` of the runner VM (passwordless sudo inside it). |
| `SF_RUNNER_VM` | libvirt domain name of the VM, used only in commands the user runs on the host. |
| `SF_RUNNER_ORG` | GitHub organization the runners serve. |
| `SF_RUNNER_LABELS` | Runner labels, for explaining which jobs land here. |
| `SF_RUNNER_BASELINE_UNIT` | systemd unit of the always-on runner. |
| `SF_RUNNER_AUTOSCALE_UNIT` | systemd unit of the autoscaler that starts on-demand runners. |
| `SF_RUNNER_AUTOSCALE_CONFIG` | Path of the autoscaler config inside the VM. |
| `SF_RUNNER_MAINTENANCE_FLAG` | Path whose existence tells self-heal to stand down. |
| `SF_RUNNER_MAX_CAP` | Highest concurrent-runner cap this skill will ever advise. |

The disk, tmpfs, memory and busy-job thresholds in the same file belong to `factory/bin/sf-runner-sample.sh`, which wakes firstmate when one is crossed; see `factory/docs/runners.md`.

## Hard limits (why each exists)

1. Never `virsh destroy`, `virsh undefine`, snapshot delete, or disk or network edits. Destroy is a power-pull that kills running CI jobs and can corrupt the guest.
2. Never restart Docker, the VM, or a runner unit while a job runs. A restart mid-job fails someone's CI. Check first (see "Is a job running?").
3. Never `pkill` or `killall` by name, `docker system prune -a`, `docker volume prune`, or delete caches broadly. Jobs share one Docker daemon, and the VM's own cleanup timers already know which containers are safe to remove.
4. Never print or copy the autoscaler token file or any runner `.credentials` file.
5. Never deregister runners or change runner groups, labels, or organization settings. That changes which repositories can build.
6. Never advise a concurrent-runner cap above `SF_RUNNER_MAX_CAP` unless the user states that exact higher number.
7. No change without the user's explicit yes for that exact change, stated back to them in one sentence first.
8. Host commands that need root (`virsh`, system sbin scripts) need the user's password. You cannot type it. Hand the user the exact command and ask them to run it as `! <command>`.

## Is a job running?

Run this before any change:

```bash
ssh "$SF_RUNNER_SSH" 'pgrep -af "[R]unner.Worker" || echo "no job running"'
```

Any output line other than `no job running` means a job is running: wait or ask the user.

## Health check (read-only, run first for any question)

```bash
ssh "$SF_RUNNER_SSH" "systemctl list-units --no-legend 'actions.runner*' | cut -c1-100; free -h | head -2; df -h / | tail -1; tail -n 1 /proc/pressure/io"
ssh "$SF_RUNNER_SSH" "sudo cat $SF_RUNNER_AUTOSCALE_CONFIG"
ssh "$SF_RUNNER_SSH" "journalctl -u $SF_RUNNER_AUTOSCALE_UNIT -n 30 --no-pager"
factory/bin/sf-runner-sample.sh --print
```

The organization runner API needs the `admin:org` scope, which many logins lack; use the VM units and journal above instead.
VM size as libvirt sees it needs root on the host, so give the user this to run: `! sudo virsh dominfo "$SF_RUNNER_VM"`.
Report back in plain words: runners online and busy, VM free memory and disk, any failed unit, and what the autoscaler last decided.

## Common tasks

| User wants | Do this | Detail |
|---|---|---|
| "Why are jobs queued or waiting?" | Health check, then read the autoscaler journal for skip reasons (RAM, swap, load, disk, cap reached) | `references/autoscaler.md` |
| Change max runners or scaling limits | Edit the config, restart the autoscaler when no on-demand runner is mid-job | `references/autoscaler.md` |
| Change VM memory | Give the user the host commands to run with sudo | `references/vm-memory.md` |
| Disk full or cleanup | Read what the timers already do; run reclaim only with a yes | `references/cleanup.md` |
| Runners missing after a reboot | Self-heal normally brings them back within minutes; check timers and journals | `references/cleanup.md` |
| One runner offline | Check its unit and journal; restart that one unit only when it has no job | below |

### Restart one stuck runner unit (needs a yes)

```bash
ssh "$SF_RUNNER_SSH" "systemctl status $SF_RUNNER_BASELINE_UNIT --no-pager | head -15"
ssh "$SF_RUNNER_SSH" 'pgrep -af "[R]unner.Worker" || echo "no job running"'
# only when no job is running and the user said yes:
ssh "$SF_RUNNER_SSH" "sudo systemctl restart $SF_RUNNER_BASELINE_UNIT"
```

On-demand ephemeral runners are single-use; do not restart them.
The autoscaler replaces them.

## How to answer

Lead with the answer, then the evidence (numbers from the commands), then the next step.
If a change is needed, state the exact command, what it changes, and what could go wrong, then wait for the yes.
If something looks broken beyond these recipes, stop and report what you saw; do not improvise fixes on the VM.
