# Agent sandbox

`agent-sandbox` runs a required command inside bubblewrap on Linux.
`codex-yolo` and `claude-yolo` supply their profiles and commands automatically.

```sh
agent-sandbox --workspace ~/Work/project --ro ~/Documents/reference --rw ~/Work/library -- bash
agent-sandbox --profile codex -- codex
agent-sandbox --profile claude -- claude
```

Repeat `--ro PATH`, `--rw PATH`, or `--env NAME` as needed. Paths must exist;
broad grants such as the whole home are refused. Explicit read-only grants
win over writable grants. Without a profile, no agent state is exposed.
`--help` and shell completions come from argc.

## Threat model

An untrusted agent working in A must not silently change what I trust while
working in B. Integrity matters more than confidentiality. Reviewing A with
host tools should be safe before approving its changes.

- Agents may edit project source and instructions. I review changes before
  deliberately executing them on the host. Staging/committing stays mine.
- Tasks within one project may share state. Other projects and global
  preferences, skills, installations and host services remain separate.
- Promoting project changes into shared configuration requires my review.
- Nix builds and Playwright with a fresh browser profile are wanted; host tmux
  control and clipboard access are not. Crostini completion notifications are
  allowed. Additional host services require an explicit trust decision.
- Direnv should require reapproval when environment inputs change, including
  imported files; approval records and host caches must remain protected.

Current controls: explicit mounts, private home/tmp/runtime/dev, filtered
environment, closed descriptors, seccomp, a new session, protected Git/Lazygit
metadata, and project-scoped agent homes. Host defaults are copied once;
project state is never written back to them.

Remaining gaps: shared networking; terminal control sequences; host review
helpers referencing editable files; direnv input/cache approval; newly created
nested metadata. These requirements are not fully enforced by this patch.

Trust the host kernel, bubblewrap, launcher and existing host processes.
Kernel exploits, resource exhaustion and intentionally running unreviewed code
are outside this boundary. Explicit grants, `--git-write` and bypass variables
weaken it. Tests cover fixtures, not every escape or live authentication flow.

## Policy

- Empty root; private home, `/tmp`, runtime directory and minimal `/dev`.
  No root/home/`/persist` bind. System tools and selected configuration are
  read-only; workspace and explicit writable grants persist.
- `.git` and `.lazygit.yml` are protected at grant roots and existing nested
  locations. Worktrees, submodules and admitted aliases are covered.
  Missing mountpoints are reserved until the last concurrent launch exits.
- Project `.agents`, `.codex`, `.claude`, `.mcp.json` and instruction files
  follow ordinary write grants. Review changes before using them outside the
  project sandbox. Parent instructions remain readable from subdirectories.
- `--git-write` permits Git metadata changes, including hooks/configuration,
  and prints a warning. `--rw .git` alone does not override protection.
- Environment allowlist, descriptor closure, capability removal, seccomp and
  `--new-session` remain enforced. Terminal output is not filtered.
- On a NixOS host with `aldur.apparmor`, the launcher enters the
  [`agent-sandbox`](apparmor/agent-sandbox) AppArmor policy. It closes abstract
  Unix sockets, io_uring, ptrace and nested namespaces. When the LSM is on and
  the policy is absent, the launch fails.
- Networking is unchanged. The Nix daemon, filtered session bus and explicitly
  configured runtime sockets retain their existing grants.

## Project state

Each profile mounts one writable home from
`~/.<agent>/agent-sandbox/projects/<project-path-hash>`. Repository subdirectories
share state; different worktrees have separate state. Non-repository launches
use their workspace path. These paths sit under the existing preserved agent
homes on Crostini.

Trusted settings, instructions and credentials are copied on first use.
Shared installations, skills and plugins are mounted read-only. Sessions,
SQLite databases, settings and credential refreshes stay within that project.
There is no host writeback or automatic import of old conversations/databases.
Global settings changes do not overwrite an existing project's copy.

Initialize/login outside the sandbox before first use. If copied credentials
expire or refresh-token rotation invalidates another copy, log in within the
affected project profile. Live OAuth refresh has not been tested.
Review proposed shared changes and apply them outside the sandbox.

## Configuration and checks

Persistent grants use `programs.aldur.<agent>.sandbox.filesystem.readOnlyPaths`
and `readWritePaths`: lists of strings, not Nix path literals. Mount defaults
live in [package.nix](package.nix); CLI assembly in
[agent-sandbox.sh](agent-sandbox.sh); state and metadata policy in
[launch.py](launch.py).

`AGENT_NO_SANDBOX=1`, `CODEX_NO_SANDBOX=1` or `CLAUDE_NO_SANDBOX=1` bypasses
applicable wrapping and prints a warning.

```sh
nix build path:.#checks.x86_64-linux.agent-sandbox path:.#checks.x86_64-linux.agent-sandbox-modules --no-link
nix build path:.#checks.x86_64-linux.agent-sandbox-apparmor --no-link
```

Tests use synthetic files, credentials and services. They cover filesystem and
metadata protection, preservation aliases, concurrency/cleanup, project state,
atomic writes, environment, descriptors, signals and seccomp. The AppArmor
check boots VMs with the policy enforced, in complain mode and absent. Optional
[CLI smoke tests](tests/cli-smoke.py) run installed agents offline.
