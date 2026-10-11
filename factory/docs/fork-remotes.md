# Fork remotes and branch protection

These are one-time manual steps.
Nothing in the factory runs them for you, because `bin/fm-update.sh` never edits remotes.

## Remotes, once per home

Run these in the main home and again in every secondmate home.
Do it only after the fork's `main` carries the factory overlay.

```sh
git remote rename origin upstream
git remote add origin https://github.com/toeydevelopment/firstmate
git fetch origin
git remote set-head origin main
```

After this, `origin` is the fork and `upstream` is `https://github.com/kunchenguid/firstmate`.
`bin/fm-update.sh` fast-forwards from `origin`, and `factory/bin/sf-sync-upstream.sh` merges from `upstream`.
If a home never had `origin` pointing at kunchenguid, add the upstream remote with `git remote add upstream https://github.com/kunchenguid/firstmate` instead of the rename.

Check the result with `git remote -v`.

## First fork update

The fork's `main` must be a plain fast-forward of upstream before the overlay lands.
Push it without `--force`: `git fetch upstream main && git push origin upstream/main:refs/heads/main`.
If GitHub rejects the push as non-fast-forward, stop and investigate instead of forcing.

## Protect the fork's main branch

Merge commits from `factory/bin/sf-sync-upstream.sh` must stay possible, so do not require linear history.
Block force-pushes and deletion, and require pull requests for overlay work:

```sh
gh api -X PUT repos/toeydevelopment/firstmate/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

Add the `sf-overlay-check` workflow as a required status check once it has run on the fork.
Never rebase or force-push the fork's `main`: every home would then report `skipped: diverged` on its next update.
