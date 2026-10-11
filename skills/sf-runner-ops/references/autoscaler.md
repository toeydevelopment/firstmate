# Autoscaler: runner count and scaling limits

This page assumes an autoscaler service (`$SF_RUNNER_AUTOSCALE_UNIT`) that keeps a baseline runner on and starts single-use runners when jobs queue.
The key names below are the common ones; read the live config to see what your autoscaler really uses.
The live config is `$SF_RUNNER_AUTOSCALE_CONFIG` inside the VM.

| Key | Meaning |
|---|---|
| `baseline_runners` | Runners kept on all the time. |
| `max_concurrent_runners` | The real cap on CI jobs at once, baseline included. |
| `max_ephemeral` | Slot count for on-demand runners. |
| `min_available_ram_mb` | Memory needed per new runner. |
| `min_free_swap_mb`, `max_load_avg`, `min_free_disk_gb` | Other guards; any one failing means "do not scale now". |
| `check_interval_seconds` | How often the autoscaler polls GitHub. |
| `idle_timeout_seconds` | How long an idle on-demand runner lives. |

A higher cap uses no memory by itself.
Runners start only when jobs wait and every guard passes.
When a guard fails, jobs wait in the GitHub queue; they do not fail.
The VM's memory size is the real ceiling on how many runners fit.

## Why are jobs waiting?

```bash
ssh "$SF_RUNNER_SSH" "journalctl -u $SF_RUNNER_AUTOSCALE_UNIT -n 60 --no-pager"
ssh "$SF_RUNNER_SSH" 'free -m | head -2; swapon --show; uptime; df -h / | tail -1'
```

Match the journal's skip reason to the guard above, then tell the user which guard blocked and by how much.

## Change the limits (needs a yes)

Never set a cap above `SF_RUNNER_MAX_CAP` unless the user states that exact higher number.
Automatic throttling and unreviewed cap changes have backfired before, so the cap value belongs to the user.
Back up the config first, change one key, and show the result:

```bash
ssh "$SF_RUNNER_SSH" "sudo cp $SF_RUNNER_AUTOSCALE_CONFIG $SF_RUNNER_AUTOSCALE_CONFIG.bak"
ssh "$SF_RUNNER_SSH" "sudo python3 - <<EOF
import json; p='$SF_RUNNER_AUTOSCALE_CONFIG'
d=json.load(open(p)); d['max_concurrent_runners']=4
json.dump(d,open(p,'w'),indent=2)
EOF"
ssh "$SF_RUNNER_SSH" "sudo cat $SF_RUNNER_AUTOSCALE_CONFIG"
```

Restart the autoscaler only when no on-demand runner is mid-job (jobs on the baseline runner are not affected):

```bash
ssh "$SF_RUNNER_SSH" 'pgrep -af "[R]unner.Worker" || echo "no job running"'
ssh "$SF_RUNNER_SSH" "sudo systemctl restart $SF_RUNNER_AUTOSCALE_UNIT && systemctl is-active $SF_RUNNER_AUTOSCALE_UNIT"
```

A live edit may be lost on the next setup run.
Tell the user the value must also land in the repository that deploys the autoscaler config, through a pull request.
Undo: copy the `.bak` file back and restart the autoscaler under the same rules.
