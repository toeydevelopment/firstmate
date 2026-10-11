# VM memory (KVM/libvirt)

All `virsh` commands need root on the host.
You cannot enter the password, so give the user each command to run as `! sudo ...`.
Use the libvirt domain name from `SF_RUNNER_VM`.

## Look

```bash
! sudo virsh dominfo "$SF_RUNNER_VM"
! sudo virsh dommemstat "$SF_RUNNER_VM"
```

Inside the VM (no sudo needed): `ssh "$SF_RUNNER_SSH" free -h`.

## How memory behaves

- KVM gives the VM host RAM only when the guest touches it.
- With a virtio memory balloon and free-page reporting on, memory the guest frees goes back to the host.
- Guest file cache counts as used until it is dropped.
- The VM's memory size is a hard ceiling: busy CI can never take more than that from the host.

## Resize (needs a yes, run by the user)

Do these in order; every step needs the user to run it:

1. Check that no job is running: `ssh "$SF_RUNNER_SSH" 'pgrep -af "[R]unner.Worker" || echo "no job running"'`.
2. Pause self-heal by creating `$SF_RUNNER_MAINTENANCE_FLAG` on the host and in the VM.
3. Back up the definition: `! sudo sh -c 'virsh dumpxml "$SF_RUNNER_VM" > /var/backups/libvirt/runner-vm-manual.xml'`.
4. Set the size in KiB (GiB x 1048576): `! sudo virsh setmaxmem "$SF_RUNNER_VM" <KiB> --config`, then `! sudo virsh setmem "$SF_RUNNER_VM" <KiB> --config`.
5. Restart gracefully: `! sudo virsh shutdown "$SF_RUNNER_VM"`, repeat `! sudo virsh domstate "$SF_RUNNER_VM"` until `shut off`, then `! sudo virsh start "$SF_RUNNER_VM"`.
6. Remove both maintenance flags, then confirm with `ssh "$SF_RUNNER_SSH" free -h`.

`--config` changes only the saved definition; it takes effect at the next start, which is why step 5 exists.
Undo: `! sudo virsh define /var/backups/libvirt/<backup>.xml`, then step 5 again.

Leave enough host RAM for the desktop and agents: warn the user before sizing the VM above roughly 60 percent of host memory.
Never use `virsh destroy` unless the user explicitly asks after a graceful shutdown hung.
