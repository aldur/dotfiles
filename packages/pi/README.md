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

- It merges the settings, keybindings, and MCP servers from [home.nix](home.nix)
  into `settings.json`, `keybindings.json`, and `mcp.json`. Declared keys replace
  existing values, including the extensions list. Other keys stay in place.
- It links `AGENTS.md` to the shared
  [agent instructions](../../modules/home/agents/AGENTS.md) and links the
  shared [skills](../../skills) under `skills/`.
- It moves an existing `AGENTS.md` or matching skill to a
  `.dotfiles-backup.*` directory before replacing it with a link. Existing
  settings and keybindings are merged in place, without such a backup.

Set `PI_CODING_AGENT_DIR` to use another directory. For Home Manager, add
extension paths through `programs.pi.settings.extensions`.

Use `packages.${system}.pi.override { selfUpdates = false; }` to run the pinned
version. Set `plugins = { };` to remove bundled plugins, or extend `pi.plugins`.
Overrides retain the standalone launcher. Home Manager writes
`.pi/agent/.home-manager`; the launcher leaves its configuration to Home Manager.

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

## Browser

Set `playwright-lazy = null` in the Pi package override to omit browser support
and its Nix installer. The Pi container images use this override.

Pi and its subagents use the native `playwright-lazy` MCP server from
[home.nix](home.nix). It starts over stdio inside `pi-yolo`. Use `codemode`
to find tools with `searchTools()` or `describeNamespace("mcp__playwright_lazy")`.
An agent with an explicit `tools` list must include `codemode`.
Run `pi mcp list` to check the connection.

[browser.nix](browser.nix) configures the
[shared Playwright MCP runtime](../../overlays/playwright.md). It enables
Chromium's sandbox. Downloads, snapshots, and screenshots go to
`.pi/browser/worker-XXXXXXXX/` under the worker's working directory. Tool
results give the file paths. These files remain readable after the session
ends; remove them when no longer needed.

To prepare the browser before an offline session, run:

```sh
pi browser-prefetch
# Or use the same sandbox as the workers:
pi-yolo browser-prefetch
```

Both commands select Pi's persistent browser cache. See the
[shared browser guide](../../overlays/playwright.md#cache-warmup) for cache
locations and cleanup.

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

- [pi-daybreak](plugins/pi-daybreak): adds `/daybreak` for `openai-codex` login.
  Open the menu, or use `blue`, `red`, `on`, `off`, `toggle`, `default`, or `status`.
  `on` restores the last tier (initially Blue). `off` sends `standard`;
  `default` leaves the request unchanged. Each session start, resume, or reload
  resets to `default`. The footer shows the requested setting, not confirmed access.
  Select a compatible model with `/model`. Red requires a Red-compatible model;
  GPT-6 Sol uses Blue, even for accounts with Red approval. See the
  [OpenAI Daybreak guide](https://developers.openai.com/api/docs/guides/daybreak).
- [pi-llama](plugins/pi-llama.nix): llama.cpp discovery and router support.
- [pi-openai-discovery](plugins/pi-openai-discovery): OpenAI-compatible model discovery.
- [pi-no-docs](plugins/pi-no-docs): removes the Pi documentation section from the default prompt.
- [pi-startup-header](plugins/pi-startup-header): hides the default startup header.
- [pi-statusline](plugins/pi-statusline): displays session status in the footer.
- [pi-throughput](plugins/pi-throughput): displays response and prompt processing rates.
- [pi-subagent](plugins/pi-subagent): stores a local copy of Pi's subagent extension.
  Supports repeated `--agent <file.md>` options and tool-call model overrides.
- [pi-system-prompt](plugins/pi-system-prompt): adds a read-only `/system-prompt` command.
- [pi-prompt-stash](plugins/pi-prompt-stash): Alt+S stores or restores the prompt.
  If both contain text, it swaps them.

All Pi tests are in [tests](tests). The package checks its extensions during
the Nix build. The
[standalone test](tests/standalone.nix) checks the managed settings and file links.
The [extension test](tests/extensions/default.nix) checks revision changes, rollback,
individual extension paths, and subagent startup without model requests.

```sh
nix build .#pi .#checks.x86_64-linux.pi-standalone .#checks.x86_64-linux.pi-extensions
```
