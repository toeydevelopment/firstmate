# Cleanup, disk, and self-heal

Most cleanup should be automatic on a well-run runner VM.
Explain what already runs before doing anything by hand.
Typical timers, which you must confirm with `systemctl list-timers` because names differ per setup:

| Kind | What it does |
|---|---|
| Job-completed hook | Clears the finished job's work directory and its labelled Docker containers. |
| Container sweep timer | Removes leftover test containers older than a couple of hours, unless a live job started before them. |
| Cache-release timer | Drops guest page cache when no job runs, so memory returns to the host. |
| Reclaim timer | Frees disk: old unused images, old temp files, capped language caches, tool cache, then `fstrim`. |
| Self-heal timer | Starts Docker and any down runner shortly after boot and every few minutes; stands down while `$SF_RUNNER_MAINTENANCE_FLAG` exists. |

```bash
ssh "$SF_RUNNER_SSH" 'systemctl list-timers --no-legend'
```

## Disk getting full

```bash
ssh "$SF_RUNNER_SSH" 'df -h / | tail -1; docker system df'
ssh "$SF_RUNNER_SSH" 'sudo du -sh /var/lib/docker /opt/hostedtoolcache 2>/dev/null | sort -h'
```

The autoscaler stops scaling when free disk is below its guard.
If disk is low, starting the reclaim unit by hand needs a yes.
It is the same job the timer runs and is safe during jobs:

```bash
ssh "$SF_RUNNER_SSH" 'systemctl list-units --all --no-legend "*reclaim*"'
# with the user's yes, start the unit named above:
ssh "$SF_RUNNER_SSH" 'sudo systemctl start <reclaim unit>.service'
```

Do not run `docker system prune -a`, `docker volume prune`, or `rm -rf` on caches yourself.
If reclaim is not enough, report the biggest users from `du` and let the user decide.

## After a reboot or power cut

Wait about five minutes, then run the health check in SKILL.md.
Everything should be back without action.
If the VM is not running, the host's journal for its self-heal unit shows why, and the start itself needs the user to run `! sudo virsh start "$SF_RUNNER_VM"`.
If a runner is down, read the VM's self-heal journal before restarting anything.
