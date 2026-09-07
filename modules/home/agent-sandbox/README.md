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
later, such as Git hooks, shell configuration and agent settings. It must
not change project B. Network access is not restricted.

The sandbox trusts the kernel, `bubblewrap`, the launcher and the other host
processes. Each extra grant, `--git-write` and each bypass variable makes
the protection weaker.

## What the command sees

- **Filesystem.** A temporary root with `/nix/store`, `/dev`, `/proc`,
  `/tmp`, `/var/tmp`, an empty home directory and an empty runtime
  directory. `/tmp` and the home directory are new for each launch.
- **Read-only.** The Nix profiles, `~/.local/bin`, some `/etc` files (users,
  hosts, DNS, TLS, Nix), and the Git, fish and direnv configuration.
- **Writable.** The workspace, the `--rw` grants and the agent state. These
  are the real host directories. Changes stay after the sandbox exits.
- **Environment.** Only `PATH`, terminal, locale, TLS and `nix-ld` variables
  pass, plus the `--env` names and the profile allowlist. `HOME`, `TMPDIR`,
  `XDG_*`, `SHELL` and `GNUPGHOME` point into the sandbox.
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

Each project gets its own agent home on the host, at
`~/.<agent>/agent-sandbox/projects/<hash>`. The hash comes from the
repository root, so all subdirectories of a repository share one home. A
worktree gets a separate home. Outside a repository, the hash comes from
the workspace path.

On the first launch the launcher copies the host defaults into the home:
`settings.json`, `CLAUDE.md` and `~/.claude.json` for Claude, `config.toml`
and `AGENTS.md` for Codex. The host directories `skills`, `plugins`,
`packages`, `bin`, `commands`, `agents`, `rules` and `output-styles` are
mounted read-only when they exist.

Sessions, databases and settings changes stay in the project home. The
launcher never copies them back to the host. A later change to a host
default does not reach an existing project home.

Credentials are the exception. The launcher mounts the host file
(`~/.claude/.credentials.json` or `~/.codex/auth.json`) writable into each
project home. Each token refresh gives a new refresh token and makes the old
one invalid. With one copy per project, a refresh in one project would log
out the host and the other projects. With one shared file, a login or a
refresh anywhere is valid everywhere.

- Codex needs a login on the host before the first launch. The launcher
  stops when `auth.json` is missing.
- Claude accepts a first login inside the sandbox. When the host file is
  missing, the launcher creates it with placeholder content.
- Log out on the host. Inside the sandbox the agent cannot delete the file.

The launcher sets `CLAUDE_CONFIG_DIR`, or `CODEX_HOME` and
`CODEX_SQLITE_HOME`, to the project home. For Codex it also writes
`sqlite_home` into the project copy of `config.toml`.

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

`AGENT_NO_SANDBOX=1`, `CODEX_NO_SANDBOX=1` or `CLAUDE_NO_SANDBOX=1` runs the
command without the sandbox and prints a warning.

Code: mount defaults in [package.nix](package.nix), argument parsing and the
`bwrap` command line in [agent-sandbox.sh](agent-sandbox.sh), agent state
and Git metadata protection in [launch.py](launch.py).

## Tests

```sh
nix build --no-link path:.#checks.x86_64-linux.agent-sandbox path:.#checks.x86_64-linux.agent-sandbox-modules
```

The first check builds a fake host in `bubblewrap`, with and without a
`/persist` path, and runs the sandbox inside it. It covers the mounts, the
environment, open files, seccomp, the bus proxy, Git metadata protection,
agent state, shared credentials and direnv. The second check verifies the
`-yolo` aliases. [cli-smoke.py](tests/cli-smoke.py) runs the installed
agents offline in the sandbox with dummy credentials.
