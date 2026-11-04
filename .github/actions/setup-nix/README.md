# Set up Nix

Install Determinate Nix and Magic Nix Cache on a Linux or macOS runner.
The action uses the GitHub Actions cache and disables FlakeHub caching,
telemetry, installer diagnostic reports, and the build timeline summary.

## Use from another repository

Add these steps to a job:

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  - uses: aldur/dotfiles/.github/actions/setup-nix@master
  - run: nix build
```

For a fixed version, replace `master` with a full commit SHA from this
repository. GitHub supports [actions in repository subdirectories][actions].
The checkout step checks out the caller's repository.

Nix omits the initial list of store paths. Build progress, warnings, and
failure logs remain visible. Use build commands without `-L` or
`--print-build-logs` to avoid streaming successful build logs.

## Inputs

All inputs are optional.

| Input | Default | Effect |
| --- | --- | --- |
| `cache` | `"true"` | Enable Magic Nix Cache. Set `"false"` for jobs that do not need to cache build results. |
| `log-lines` | `"1000"` | Number of build log lines shown after a build fails. |
| `print-missing` | `"false"` | Print the initial list of paths to build or download. |
| `eval-cores` | `""` | Keep the installed setting. Set a value to override the number of evaluation threads. |
| `trust-runner-user` | `"true"` | Trust the runner user so Magic Nix Cache can configure the store. |

This repository sets evaluation threads only for the full check set:
the `nix flake check` command in [ci.yml](../../workflows/ci.yml) and the
`nix eval` command in [build-flake-checks.sh](../../scripts/build-flake-checks.sh)
use one thread for Linux to limit memory use, and all available cores
(`eval-cores = 0`) for the smaller Darwin check set. Other commands keep the
installed setting. These settings do not change build parallelism.

For example, to show fewer lines after a failure:

```yaml
- uses: aldur/dotfiles/.github/actions/setup-nix@master
  with:
    log-lines: "200"
```

[actions]: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#example-using-a-public-action-in-a-subdirectory
