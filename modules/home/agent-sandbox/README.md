# Agent sandbox

On Linux, `agent-sandbox` runs a required command inside bubblewrap.
`codex-yolo` and `claude-yolo` select their mount profiles and supply their
commands and flags automatically.
It starts with an empty root, private home, temporary directories and runtime
directory. It mounts the launch directory read/write and a list of system
tools and configuration read-only. `/persist` and unrelated host directories
are not mounted. Mount groups live in [package.nix](package.nix);
argument parsing and assembly live in [agent-sandbox.sh](agent-sandbox.sh).
The module and agent profiles live in [default.nix](default.nix), with shared
NixOS options in [options.nix](options.nix).
The command uses the repository's `writeArgcApplication` helper, with generated
help and Bash, Zsh and Fish completions from the script's argc annotations.

## Add paths for one command

Use `agent-sandbox` for any command:

```sh
agent-sandbox \
  --workspace ~/Work/project \
  --ro ~/Documents/reference \
  --rw ~/Work/shared-library \
  -- bash

agent-sandbox --profile codex --rw ~/Work/shared-library -- codex
agent-sandbox --profile claude --rw ~/Work/shared-library -- claude
```

Without `--profile`, the base sandbox includes tools and the workspace, with
no agent state. `--profile codex` and `--profile claude` add the corresponding
agent's state and Nix settings. Profiles are available when that agent is
enabled. The command after `--` is always required, even with a profile; it
can be any program. Existing `codex-yolo` and `claude-yolo` usage is unchanged.

`--workspace` replaces the default launch directory. Repeat `--ro` and `--rw`
for more paths, including files. Put the command and its arguments after `--`.
Paths may be relative to the launch directory, absolute, or start with `~/`.
Quote paths with spaces. Missing paths fail at launch. Whole-root and whole-home
grants are refused. Read-only mounts are applied after writable mounts, so
`--ro` can restrict a directory inside the writable workspace.

## Add paths in Nix

Both agent profiles expose the same options:

```nix
programs.aldur.codex.sandbox.filesystem = {
  readOnlyPaths = [ "~/Documents/reference" ];
  readWritePaths = [ "~/Work/shared-library" ];
};

programs.aldur.claude-code.sandbox.filesystem = {
  readOnlyPaths = [ "/srv/documentation" ];
  readWritePaths = [ "~/Work/shared-library" ];
};
```

These must be strings, not Nix path literals: their contents should not be
copied into the Nix store. The selected profile's configured paths and
command-line paths are combined.

## State and services

The selected agent's existing state is an explicit writable exception:
`~/.codex` for Codex, and `~/.claude` plus `~/.claude.json` for Claude. Existing
standalone installations are mounted read-only. Other home files created by
the command are ephemeral. Authentication and configuration within admitted
state remain accessible to the agent; this change does not separate those
from session data. Workspace contents, including `.git`, remain writable.

Host `/run/dbus`, `/run/pcscd`, shared `/tmp` sockets (including SSH agents and
X11), and hardware device nodes are absent. Bubblewrap creates a minimal
private `/dev`. The default and any custom host GnuPG homes are absent;
`GNUPGHOME` points to a private, ephemeral directory. GPG can start a new
agent there without accessing the host's keys or sockets.

Network access stays enabled, including host TCP services and Linux abstract
Unix sockets. This is not network isolation; those endpoints do not depend on
filesystem mounts. The filtered session bus and any configured
`extraRuntimeDirAllowlist` entries are exposed. `sandbox.allowNixDaemon`
defaults to `true`, exposing the host daemon socket when present so builds
work with a read-only Nix store. Set it to `false` to omit the socket. Daemon
access carries the invoking user's Nix permissions, so a trusted Nix user
is unsuitable for confinement. The store itself is readable, including any
data that was previously copied into it.

## Environment and syscalls

The wrapper clears the inherited environment and passes an explicit list of
tool, terminal, locale and certificate settings (listed in
[agent-sandbox.sh](agent-sandbox.sh)). Desktop endpoints, SSH agent variables,
shell startup hooks, and unrelated API tokens are not passed by default.
The Claude profile also preserves the settings supplied by `claude-yolo`.

Grant additional environment variables by name when a command needs them:

```sh
agent-sandbox --profile codex --env OPENAI_API_KEY --env HTTPS_PROXY -- codex
```

For persistent profile settings:

```nix
programs.aldur.codex.sandbox.extraEnvironmentAllowlist = [ "OPENAI_API_KEY" ];
```

Values come from the launch environment, so secrets stay out of the Nix
configuration. Missing variables are omitted. Sandbox home, temporary and
runtime locations override explicit environment grants. Files within granted
paths, including agent state, can still contain secrets.

Every sandbox uses `--new-session`, drops capabilities, and requires a seccomp
filter. The filter denies terminal injection/control requests `TIOCSTI` and
`TIOCLINUX`, host kernel keyring operations, `bpf`, `perf_event_open`, and
`userfaultfd`. It applies to descendants and compatible ABIs, independently
of the host's TIOCSTI sysctl. An unsupported kernel fails at launch; there is
no automatic fallback. Normal terminal input, mode and size operations remain
available through inherited stdin/stdout/stderr.
Other inherited file descriptors are closed before starting either the proxy
or sandbox, so an open host file or socket cannot bypass the mount policy.

This is a small syscall denylist, not a general syscall allowlist. Nested
sandboxes remain supported. See [Bubblewrap's security notes](https://github.com/containers/bubblewrap#limitations)
for the terminal and service-access concerns behind these choices.

## Bypass

`AGENT_NO_SANDBOX=1` bypasses the sandbox for any command or profile.
`CODEX_NO_SANDBOX=1` and `CLAUDE_NO_SANDBOX=1` continue to bypass their respective
profiles, including when invoked through the `-yolo` aliases.
The wrapper prints a warning to stderr before running the command directly;
arguments and exit status are preserved. For example:

```text
agent-sandbox: WARNING: CODEX_NO_SANDBOX=1; running without the sandbox.
```

## Tests

```sh
nix build .#checks.x86_64-linux.agent-sandbox .#checks.x86_64-linux.agent-sandbox-modules
```

The integration check runs the real wrapper in a synthetic host namespace,
both with and without `/persist`. It covers filesystem grants and symlinks,
host sockets/devices/GnuPG state, environment grants, session bus filtering,
Nix socket policy, seccomp enforcement and failure, descendant restrictions,
Git and nested sandboxes, PTY input and Ctrl-C, cleanup, argument forwarding,
exit status, inherited descriptors, bypass warnings, and generated completions.
Module checks cover installation and aliases with neither agent, either agent,
or both enabled.
Run the integration check on each target kernel, especially Crostini: the
synthetic filesystem covers its persistence layout but cannot emulate a
foreign ChromeOS kernel.
