# playwright-lazy

[Pi](../packages/pi/README.md#browser) and
[Claude](../modules/home/claude/default.nix) use the same `pkgs.playwright-lazy`
package from [slim.nix](slim.nix), registered as `playwright-lazy` in both
clients. It provides Playwright MCP with Chromium installed on first use.
The [flake lock](../flake.lock) pins the MCP
server and browser. On Linux, [playwright-browser.nix](playwright-browser.nix)
keeps the Chromium headless shell and trims its runtime dependencies.

## First use

[playwright-lazy.nix](playwright-lazy.nix) installs the browser on first use.
Starting MCP and discovering tools do not install it. The first browser launch
builds the pinned Nix recipe and can take several minutes. Network access is
needed unless the required inputs are available. A failed installation can be
retried.

Concurrent workers share one installation. Both clients request isolated
browser contexts without personal cookies or profiles. The launcher does not
change sandbox permissions. Private-store containers must include the browser
closure in their store seed.

## Cache warmup

The MCP package includes `playwright-browser-prefetch`. It installs the browser
without opening a page. Run it before an offline session and use the state
directory for the intended client:

| Client | State directory |
| --- | --- |
| Pi | `$PI_CODING_AGENT_DIR/browser`, or `~/.pi/agent/browser` |
| Claude | `$CLAUDE_CONFIG_DIR/browser`, or `~/.claude/browser` |
| Direct MCP use | `$XDG_CACHE_HOME/playwright-nix`, or `~/.cache/playwright-nix` |

Set `PLAYWRIGHT_BROWSER_STATE_DIR` when running the generic prefetch command
to select a client directory. Pi provides [dedicated commands](../packages/pi/README.md#browser)
that select its directory automatically.

Each pin has a Nix garbage-collection root in its state directory. This directory
must be visible to the Nix daemon. Remove obsolete entries to permit Nix garbage
collection. Browser processes end with their sessions; the installed package
remains available.
