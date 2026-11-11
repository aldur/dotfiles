# CI security

## Rules for all workflows

- Each workflow starts with `contents: read` or with no permissions. A job
  that needs more declares it, with the reason in a comment.
- Each external action is pinned to a full commit SHA. Dependabot opens the
  pull requests that update the pins.
- `actions/checkout` runs with `persist-credentials: false`.
- No workflow uses `pull_request_target` or `workflow_run`.
- A pull request from a fork gets a read-only token and no secrets. GitHub
  enforces this. Dependabot pull requests get a read-only token too.

## Jobs with a write token

| Workflow | Job | Permission | When |
|---|---|---|---|
| `ci.yml` | `containers` | `packages: write`, `id-token: write`, `attestations: write` | Not on `workflow_dispatch` |
| `publish-apple-container.yml` | push, manifest and attest jobs | `packages: write`; attest also `id-token: write`, `attestations: write` | Called by `ci.yml`, or manual |
| `baguette-image.yml` | `attest` | `id-token: write`, `attestations: write` | Manual only |
| `update-pinned-packages.yml` | `pull-request` | `contents: write`, `pull-requests: write`, `actions: write` | Weekly, or manual |

`ci.yml` publishes images only on a push to `master` or `staging`. In all
other runs, `containers` builds the images as a test and skips the steps
that publish and sign.

## Automated package updates

`update-pinned-packages.yml` has three jobs.

1. `discover` and `build` run `nix-update` and build the new version. Their
   token is read-only. The only output of `build` is a text patch.
2. `pull-request` applies the patch, pushes the branch
   `automated/update-<package>` and opens the pull request. This job runs
   no code from the patch.
3. The same job starts `ci.yml` on the branch with `workflow_dispatch`. A
   pull request from `GITHUB_TOKEN` does not start `pull_request` workflows.

A bump takes only an upstream state that is at least three days old. See
"Cooldown" in `packages/update-pins/README.md`. The repositories of the
owner of this repository are exempt.

The dispatched run builds code that nobody reviewed. For this reason
`containers` does not run on `workflow_dispatch`, and all other jobs of
`ci.yml` have a read-only token.

`GITHUB_TOKEN` cannot change files in `.github/workflows/`. GitHub refuses
such a push. It can change the local actions in `.github/actions/`.

## Ruleset

`contents: write` is not limited to one branch. The ruleset in
`.github/rulesets/` closes this gap. Only a repository administrator can
create, update or delete `master` and `staging`. `GITHUB_TOKEN` is not an
administrator.

Apply it one time:

```sh
gh api -X POST repos/aldur/dotfiles/rulesets --input .github/rulesets/protect-branches.json
```

Show the rules that are active on `master`:

```sh
gh api repos/aldur/dotfiles/rules/branches/master
```

## Remaining risks

- A defective `pull-request` job can push to branches other than `master`
  and `staging`. Such a push publishes nothing.
- A pull request from a branch of this repository runs `containers` with
  `packages: write`. Only an account with write access can make such a
  branch.
- A manual run of `publish-apple-container.yml` or `baguette-image.yml`
  publishes or signs the code of the branch that you select. Examine the
  branch first.
