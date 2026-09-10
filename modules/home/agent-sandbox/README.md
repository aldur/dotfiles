# Agent sandbox

`agent-sandbox` runs a command in `bubblewrap` on Linux. The command sees a
new filesystem that contains only the paths listed in this document. The
rest of the host is not visible. `codex-yolo` and `claude-yolo` use it with
the matching `--profile`.

```sh
agent-sandbox --profile claude -- claude
agent-sandbox --profile codex -- codex
agent-sandbox --workspace ~/Work/project --ro ~/Documents/reference --rw ~/Work/library -- bash
```

| Option | Effect |
| --- | --- |
| `--profile NAME` | Also mount the state of `codex` or `claude`. Without it, no agent state is mounted. |
| `--workspace DIR` | The writable project directory. Default: the current directory. |
| `--ro PATH` | Also mount this file or directory, read-only. Repeatable. |
| `--rw PATH` | Also mount this file or directory, writable. Repeatable. |
| `--env NAME` | Also pass this environment variable. Repeatable. |
| `--git-write` | Let the command write Git metadata for this launch. Prints a warning. |

Each path must exist. The launcher refuses large grants such as `/`, `/home`,
your home directory, `/persist`, `/tmp`, `/nix` and `/etc`. It checks the
real path behind a symlink. It applies read-only mounts after writable
mounts, so a `--ro` path inside a writable directory stays read-only.

## Goal

An agent that works on project A must not change the files the host runs
later, such as Git hooks and shell configuration. It must not change
project B. Network access is not restricted.

The agent state is shared with the host. A sandboxed agent can change the
hooks, MCP servers and instructions that the host runs later. The sandbox
protects against mistakes and against access to the rest of the host, not
against an agent that targets its own configuration.

The sandbox trusts the kernel, `bubblewrap`, the launcher and the other host
processes. Each extra grant and `--git-write` makes the protection weaker.

## What the command sees

- **Filesystem.** A temporary root with `/nix/store`, `/dev`, `/proc`,
  `/tmp`, `/var/tmp`, an empty home directory and an empty runtime
  directory. `/tmp` and the home directory are new for each launch.
- **Read-only.** The Nix profiles, `~/.local/bin`, some `/etc` files (users,
  hosts, DNS, TLS, Nix), and the Git, fish and direnv configuration.
- **Writable.** The workspace, the `--rw` grants and the agent state. These
  are the real host directories. Changes stay after the sandbox exits.
- **Environment.** Only `PATH`, `EDITOR`, `VISUAL`, terminal, locale, TLS and
  `nix-ld` variables pass, plus the `--env` names and the profile allowlist.
  `HOME`, `TMPDIR`, `XDG_*`, `SHELL` and `GNUPGHOME` point into the sandbox.
- **Services.** The Nix daemon socket, for builds (`allowNixDaemon`). A
  session bus proxy that reaches only the listed bus names
  (`extraDbusTalk`). Selected sockets from the runtime directory
  (`extraRuntimeDirAllowlist`).
- **Isolation.** Own user, PID, IPC and UTS namespaces. No capabilities. A
  seccomp filter. A new session, so the command cannot type into the parent
  terminal. Open files of the parent shell are closed. The sandbox stops
  when the launcher stops. Terminal output is not filtered.

## Protected Git metadata

The agent must not add Git hooks or change Git configuration. The launcher
mounts `.git` and `.lazygit.yml` read-only:

- at the root of each writable grant and in each nested repository,
- in worktrees and submodules, through the `gitdir:` pointer,
- through hard links, so a second name for the same file is protected too.

When one of these files does not exist, the launcher creates an empty
placeholder, so the agent cannot create it. The placeholder is removed when
the last sandbox that uses it exits.

`--git-write` disables this protection for one launch. `--rw .git` does not.

The agent can edit all other files, including `CLAUDE.md`, `AGENTS.md`,
`.mcp.json` and the `.claude` or `.codex` directory of the project. Review
these changes before you use them on the host.

## Agent state

The sandbox mounts the host state of the selected agent writable: `~/.codex`
for Codex, `~/.claude` and `~/.claude.json` for Claude. Sessions, settings,
memory and credentials are the same inside and outside the sandbox, in both
directions. A session that starts in the sandbox continues on the host with
`--resume`, and the other way round. The agent installation under that
state stays read-only.

`~/.claude.json` is a file mount. A rename over a mount point fails with
`EBUSY`; Claude Code 2.1 writes the file in place, so `claude mcp add` and
the startup writes reach the host. When the file is missing, the launcher
creates it before the first launch.

## Direnv

Direnv approvals and caches live in the sandbox home. The launcher refuses
to mount the host direnv state writable, also through a `/persist` path.
See the [direnv policy](../../shared/programs/direnv/README.md).

## Configuration

Set permanent grants per agent with
`programs.aldur.<agent>.sandbox.filesystem.readOnlyPaths` and
`readWritePaths`. Use strings, not Nix paths, or the contents go into the
Nix store. The other options are `allowNixDaemon`,
`extraEnvironmentAllowlist`, `extraRuntimeDirAllowlist` and `extraDbusTalk`.
See [options.nix](options.nix).

Code: mount defaults in [package.nix](package.nix), argument parsing and the
`bwrap` command line in [agent-sandbox.sh](agent-sandbox.sh), agent state
and Git metadata protection in [launch.py](launch.py).

## Tests

```sh
nix build --no-link -L \
  path:.#checks.x86_64-linux.agent-sandbox \
  path:.#checks.x86_64-linux.agent-sandbox-transport \
  path:.#checks.x86_64-linux.agent-sandbox-modules \
  path:.#checks.x86_64-linux.agent-yolo-cli
```

All four checks run in CI on Linux (replace `x86_64-linux` with
`aarch64-linux` on ARM). Each uses a disposable synthetic host.

- `agent-sandbox` covers mounts, environment, open files, seccomp, the bus
  proxy, Git metadata protection, shared agent state and direnv, with and
  without `/persist`.
- `agent-sandbox-transport` runs the pinned Codex and Claude clients through
  the actual module-generated YOLO launchers and requires completed model
  turns with the expected text. A local HTTPS server returns fixed Responses
  and Messages event streams. It covers plain CA files and NixOS
  `/etc/static` symlinks, checks a control outside the agent
  sandbox, and requires rejection of an untrusted CA and a wrong hostname.
  Certificate failures must produce a TLS rejection alert (Codex) or an explicit
  certificate error (Claude), with no HTTP request reaching the server. A timeout
  cannot pass the test. It uses a generated CA, a temporary home and a private
  network namespace, so it needs no account or public network access.
- `agent-sandbox-modules` evaluates the agent enable/disable combinations
  and executes the generated `codex-yolo` and `claude-yolo` scripts against
  a recording client. It checks argument boundaries, editor variables,
  exit status, actual sandbox selection, `--no-sandbox`, Claude trust and
  refresh modes, and both Codex standalone installation layouts.
- `agent-yolo-cli` runs the flake-pinned Codex and Claude clients through
  those same generated launchers in real PTYs. It types a draft, opens an
  external editor with Ctrl-G, verifies the draft reaches the editor and
  the edited text returns to the composer, then exits and checks terminal
  restoration. It covers `EDITOR` fallback and `VISUAL` precedence.

The wrapper and CLI checks use [yolo-e2e.py](tests/yolo-e2e.py), dummy
configuration and credentials, a cleared host environment and a network
namespace with no external access. They make no model calls. PTY failures
include the rendered terminal screen and every interaction has a deadline.
These checks cover local launch and editing behavior; authenticated model
responses and remote services need separate online testing.

[cli-smoke.py](tests/cli-smoke.py) remains an optional check of locally
installed native clients' version, help, authentication status and Codex
app-server startup. It does not replace the required launcher/PTY checks.

After updating the standalone clients, run the transport check against them:

```sh
nix build path:.#checks.x86_64-linux.agent-sandbox-transport.runner -o /tmp/agent-transport-runner
/tmp/agent-transport-runner/bin/agent-sandbox-transport-test \
  --codex ~/.local/bin/codex --claude ~/.local/bin/claude
```

Use `--agent codex` or `--agent claude` to select one client. Omitted binary
overrides use the flake-pinned installation.

The transport fixture tests HTTPS Responses and Messages requests. It does
not certify live account authentication, WebSocket transport, or third-party
MCP services.
