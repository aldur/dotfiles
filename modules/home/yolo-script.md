# `-yolo` launchers

`codex-yolo` and `claude-yolo` use
[`agent-sandbox`](agent-sandbox/README.md) with the matching `--profile`.

```sh
codex-yolo --ro ~/dotfiles --workspace .
claude-yolo --ro ~/dotfiles --workspace . -- --resume
codex-yolo --kvm
claude-yolo --kvm
codex-yolo --tun
codex-yolo --docker
claude-yolo --docker
codex-yolo --journal
```

The `*-yolo` launchers accept the same sandbox options before the agent
arguments, with the matching agent profile selected by default. Use `--`
to end wrapper options explicitly; otherwise the first unrecognized argument
starts the agent arguments. Sandbox options cannot be used with `--no-sandbox`
or when the agent sandbox is disabled.

Interactive shells block `claude`, `codex`, and `pi` when the matching agent
is enabled. Use its `-yolo` command instead. The guard is a shell alias; it
does not block scripts or direct executable paths. Containers retain their
existing commands. `claude-yolo update` and `codex-yolo update` run the
respective updater on the host.

## Claude state

Host-side Claude settings, workspace-trust and refresh-stamp updates use
[checked file descriptors](claude/claude-state.py). Symlinks below the host home,
multiply-linked files, special files, wrong owners and group/other-writable
state are rejected. Unsafe state stops the operation without following it.
These writes preserve bind-mounted inodes and are not crash-atomic. JSON is
transformed before writing, and refresh stamps are written only after a
successful fetch. No `settings.json.tmp` or `yolo-refresh.next` is created.
This does not make shared hooks or other executable configuration trusted.

## Tests

```sh
nix build --no-link -L \
  path:.#checks.x86_64-linux.agent-sandbox-transport \
  path:.#checks.x86_64-linux.agent-sandbox-modules \
  path:.#checks.x86_64-linux.agent-yolo-cli
```

These checks run in CI on Linux (replace `x86_64-linux` with
`aarch64-linux` on ARM). Each uses a disposable synthetic host.

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

The wrapper and CLI checks use [yolo-e2e.py](agent-sandbox/tests/yolo-e2e.py), dummy
configuration and credentials, a cleared host environment and a network
namespace with no external access. They make no model calls. PTY failures
include the rendered terminal screen and every interaction has a deadline.
These checks cover local launch and editing behavior; authenticated model
responses and remote services need separate online testing.

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
