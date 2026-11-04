# Pi

Run Pi with the settings, skills, and extensions from this repository. It can
discover models on llama.cpp and OpenAI-compatible servers. Uses a pinned Pi
version unless a self-managed installation exists. Run `pi update` to update
that installation.

## Run

```sh
nix run .#pi
nix run .#pi-yolo
```

On Linux, `pi-yolo` uses the [agent sandbox](../../modules/home/agent-sandbox/README.md).
To reach a local model server, use:

```sh
nix run .#pi-yolo -- --network host
```

On macOS, `pi-yolo` runs on the host. See the
[container guide](../../base_hosts/pi-container/README.md) for Apple container.

On each `nix run .#pi` or `nix run .#pi-yolo`, the standalone wrapper updates
the Pi agent directory, `~/.pi/agent` by default:

- It merges the settings and keybindings from [home.nix](home.nix) into
  `settings.json` and `keybindings.json`. Declared keys replace existing
  values, including the extensions list. Other keys stay in place.
- It links `AGENTS.md` to the shared
  [agent instructions](../../modules/home/agents/AGENTS.md) and links the
  shared [skills](../../skills) under `skills/`.
- It moves an existing `AGENTS.md` or matching skill to a
  `.dotfiles-backup.*` directory before replacing it with a link. Existing
  settings and keybindings are merged in place, without such a backup.

Set `PI_CODING_AGENT_DIR` to use another directory. For Home Manager, add
extension paths through `programs.pi.settings.extensions`.

The package definitions are in [overlay.nix](overlay.nix). The standalone
wrapper is in [standalone.nix](standalone.nix).

## Environment variables

| Variable | Purpose | Default |
| --- | --- | --- |
| `PI_CODING_AGENT_DIR` | Pi settings, skills, and session directory. | `~/.pi/agent` |
| `LLAMA_BASE_URL` | llama.cpp API URL, including `/v1`. | Unset; discovery is disabled. |
| `LLAMA_API_KEY` | llama.cpp API key. | `no-key` |
| `PI_OPENAI_BASE_URL` | OpenAI-compatible API URL, including `/v1`. | Unset; discovery is disabled. |
| `PI_OPENAI_API_KEY` | OpenAI-compatible API key. | `no-key` |
| `PI_OPENAI_PROFILE` | models.dev provider ID for model metadata. | Unset; use endpoint metadata. |
| `PI_TELEMETRY` | Pi telemetry setting. | `0` |
| `PI_SKIP_VERSION_CHECK` | Skip Pi's startup version check. | `1` for normal runs. |
| `PNPM_HOME` | Self-managed Pi installation directory. | `${XDG_DATA_HOME:-~/.local/share}/pnpm` on Linux; `~/Library/pnpm` on macOS. |

For `pi-yolo`, use `--env LLAMA_API_KEY` to pass the llama.cpp key into the
sandbox. See the [sandbox guide](../../modules/home/agent-sandbox/README.md) for
environment handling.

## Settings and skills

The defaults in [home.nix](home.nix) use Pi's regular terminal mode and show
startup messages. Up and Ctrl+P move the cursor up; Down moves it down. The
forward model-cycle shortcut is disabled. The [wrapper](pi.nix) disables Pi
telemetry and its automatic version check by default.

Pi uses the shared [skills](../../skills) and
[agent instructions](../../modules/home/agents/AGENTS.md).

The `tavily-search` skill uses the bundled `tvly` command to search the web and
read URLs. Search and extraction work without a key, subject to Tavily's rate
limits. Set `TAVILY_API_KEY` to use an account. The
[package](../tavily-cli/default.nix) pins the CLI, SDK, and upstream skill.

## Models

The [pi-llama](plugins/pi-llama.nix) extension discovers models on a llama.cpp server. Set
`LLAMA_BASE_URL` to enable it. Use the server's API URL, including `/v1`. The extension can
load models and show loading progress on a llama.cpp router. Local patches add
model capability discovery, reasoning settings, and startup fixes. Discovery,
loading, and progress errors are logged as warnings. Model switches cancel
pending requests without a warning.

The [OpenAI-compatible extension](plugins/pi-openai-discovery/index.ts)
discovers models from `/v1/models`. For example:

```sh
export PI_OPENAI_BASE_URL=http://localhost:8080/v1
export PI_OPENAI_API_KEY=your-api-key
pi
```

Set `PI_OPENAI_API_KEY` if the server requires a key. Optionally, set
`PI_OPENAI_PROFILE` to a models.dev provider ID. The profile supplies metadata
for matching model IDs.
Without a profile, the extension uses metadata from the endpoint. It warns and
uses an 8,192-token context when no context length is available. Open `/model`
to refresh the list. A failed refresh keeps the last list for that session.

The full models.dev catalog is built from a pinned upstream revision in
[models-catalog](models-catalog/default.nix). The catalog and its generator
use the upstream dependency lock. The [update workflow](../../.github/workflows/update-pinned-packages.yml)
checks the catalog pin.
Model filenames use hexadecimal IDs during the build to prevent case
collisions on macOS. The generator restores the original IDs. Build checks
cover case differences and model aliases.

## Extensions

- [pi-llama](plugins/pi-llama.nix): llama.cpp discovery and router support.
- [pi-openai-discovery](plugins/pi-openai-discovery): OpenAI-compatible model discovery.
- [pi-no-docs](plugins/pi-no-docs): removes the Pi documentation section from the default prompt.
- [pi-startup-header](plugins/pi-startup-header): hides the default startup header.
- [pi-statusline](plugins/pi-statusline): displays session status in the footer.
- [pi-throughput](plugins/pi-throughput): displays response and prompt processing rates.
- [pi-subagent](plugins/pi-subagent): packages Pi's subagent extension.
- [pi-system-prompt](plugins/pi-system-prompt): adds a read-only `/system-prompt` command.

The package checks its extensions during the Nix build. The
[standalone test](standalone-test.nix) checks the managed settings and file links.
The [extension test](tests/extensions/default.nix) checks revision changes, rollback,
individual extension paths, and subagent startup without model requests.

```sh
nix build .#pi .#checks.x86_64-linux.pi-standalone .#checks.x86_64-linux.pi-extensions
```
