{ pkgs, pi }:
let
  inherit (pkgs) lib;
  probe = pkgs.writeTextDir "index.ts" ''
    import * as fs from "node:fs";
    export default function(pi) {
      pi.on("session_start", () => {
        fs.writeFileSync(process.env.PI_TEST_LOG, JSON.stringify({
          extensions: JSON.parse(process.env.DOTFILES_PI_EXTENSIONS),
          tools: pi.getAllTools().map(tool => tool.name),
          commands: pi.getCommands().map(command => command.name),
        }));
        process.exit(0);
      });
    }
  '';
  configured = pi.override {
    selfUpdates = false;
    plugins = pi.plugins // { ci-repair-session = probe; };
  };
  bare = configured.override { plugins = { }; };
  withoutBrowser = bare.override { playwright-lazy = null; };
  home = (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ../home.nix
      {
        options.home = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.anything; default = { }; };
        config.programs.pi = {
          enable = true;
          settings = { tuiMode = "minimal"; retry.enabled = false; };
          keybindings."tui.editor.cursorUp" = [ "ctrl+k" ];
        };
      }
    ];
  }).config;
  managed = pkgs.writeText "pi-test-managed.json" (
    builtins.toJSON { inherit (home.programs.pi) settings keybindings mcp; }
  );
in
assert configured.plugins.ci-repair-session == probe;
assert bare.plugins == { };
assert pi.browserEnabled && !withoutBrowser.browserEnabled;
pkgs.runCommand "pi-standalone-test" { } ''
  export HOME="$TMPDIR/home"
  export PI_CODING_AGENT_DIR="$HOME/agent"
  export PNPM_HOME="$HOME/pnpm"
  mkdir -p "$PI_CODING_AGENT_DIR/skills/writing-well"
  printf 'local instructions' > "$PI_CODING_AGENT_DIR/AGENTS.md"
  printf 'local skill' > "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md"

  ${pkgs.lib.getExe pi} --version
  ${pkgs.lib.getExe pi} browser-prefetch --help
  test ! -e "$PI_CODING_AGENT_DIR/browser"
  backup=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backup[@]}" = 1
  test "$(cat "''${backup[0]}/AGENTS.md")" = 'local instructions'
  test "$(cat "''${backup[0]}/skills/writing-well/SKILL.md")" = 'local skill'
  cmp "$PI_CODING_AGENT_DIR/AGENTS.md" ${../../../modules/home/agents/AGENTS.md}
  cmp "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md" ${../../../skills/writing-well/SKILL.md}
  cmp "$PI_CODING_AGENT_DIR/skills/tavily-search/SKILL.md" ${pkgs.tavily-cli.skills}/tavily-search/SKILL.md
  test -f "$PI_CODING_AGENT_DIR/skills/tavily-search/references/setup.md"

  ${pkgs.lib.getExe pi} --version
  backups=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backups[@]}" = 1

  rm "$PI_CODING_AGENT_DIR/skills/writing-well"
  ln -s /old/skill "$PI_CODING_AGENT_DIR/skills/writing-well"
  ${pkgs.lib.getExe pi} --version
  cmp "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md" ${../../../skills/writing-well/SKILL.md}
  backups=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backups[@]}" = 2

  ${lib.getExe pkgs.python3} - "$PI_CODING_AGENT_DIR" <<'PY'
  import json, sys
  from pathlib import Path
  agent = Path(sys.argv[1])
  assert json.loads((agent / "settings.json").read_text())["tuiMode"] == "regular"
  assert "ctrl+p" in json.loads((agent / "keybindings.json").read_text())["tui.editor.cursorUp"]
  browser = json.loads((agent / "mcp.json").read_text())["mcpServers"]["playwright-lazy"]
  assert Path(browser["command"]).is_file()
  assert browser["exposure"] == "codemode"
  PY

  mkdir -p "$PNPM_HOME/bin"
  cat > "$PNPM_HOME/bin/pi" <<'SH'
  #!${pkgs.runtimeShell}
  echo self-managed-fixture
  SH
  chmod +x "$PNPM_HOME/bin/pi"
  test "$(${lib.getExe pi} --version)" = self-managed-fixture
  export PI_CODING_AGENT_DIR="$HOME/override-agent"
  test "$(${lib.getExe configured} --version)" = '${pkgs.pi-coding-agent.version}'
  cmp "$PI_CODING_AGENT_DIR/AGENTS.md" ${../../../modules/home/agents/AGENTS.md}
  test -L "$PI_CODING_AGENT_DIR/skills/writing-well"
  test -f "$PI_CODING_AGENT_DIR/settings.json"
  test "$(${lib.getExe bare} --version)" = '${pkgs.pi-coding-agent.version}'

  export PI_TEST_LOG="$TMPDIR/loaded.json"
  cd "$HOME"
  ${lib.getExe configured} --offline --no-session -p fixture
  ${lib.getExe pkgs.python3} - "$PI_TEST_LOG" <<'PY'
  import json, sys
  receipt = json.load(open(sys.argv[1]))
  assert receipt["extensions"] == ${builtins.toJSON (map (plugin: plugin.entryPoint or "${plugin}/index.ts") (lib.attrValues configured.plugins))}
  assert "subagent" in receipt["tools"], receipt
  assert "system-prompt" in receipt["commands"], receipt
  PY
  rm "$PI_TEST_LOG"
  ${lib.getExe bare} -e ${probe}/index.ts --offline --no-session -p fixture
  ${lib.getExe pkgs.python3} - "$PI_TEST_LOG" <<'PY'
  import json, sys
  receipt = json.load(open(sys.argv[1]))
  assert receipt["extensions"] == [], receipt
  assert "subagent" not in receipt["tools"], receipt
  assert "system-prompt" not in receipt["commands"], receipt
  PY

  # Home Manager owns these files. Startup must preserve their contents and links.
  export PI_CODING_AGENT_DIR="$HOME/managed-agent"
  mkdir -p "$PI_CODING_AGENT_DIR/skills/writing-well" "$HOME/.config/agents"
  printf 'managed instructions' > "$HOME/.config/agents/AGENTS.md"
  ln -s "$HOME/.config/agents/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"
  ln -s ${../../../skills/writing-well/SKILL.md} "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md"
  printf %s ${lib.escapeShellArg home.home.file.".pi/agent/.home-manager".text} > "$PI_CODING_AGENT_DIR/.home-manager"
  ${lib.getExe configured.configSync} ${managed} "$PI_CODING_AGENT_DIR"
  cp "$PI_CODING_AGENT_DIR/settings.json" "$TMPDIR/settings.json"
  cp "$PI_CODING_AGENT_DIR/keybindings.json" "$TMPDIR/keybindings.json"
  cp "$PI_CODING_AGENT_DIR/mcp.json" "$TMPDIR/mcp.json"
  for executable in ${lib.getExe configured} ${lib.getExe bare} ${lib.getExe configured}; do
    rm -f "$PI_TEST_LOG"
    flags=()
    if [ "$executable" = ${lib.getExe bare} ]; then
      flags=(-e ${probe}/index.ts)
    fi
    "$executable" "''${flags[@]}" --offline --no-session -p fixture
    test -s "$PI_TEST_LOG"
    cmp "$PI_CODING_AGENT_DIR/settings.json" "$TMPDIR/settings.json"
    cmp "$PI_CODING_AGENT_DIR/keybindings.json" "$TMPDIR/keybindings.json"
    cmp "$PI_CODING_AGENT_DIR/mcp.json" "$TMPDIR/mcp.json"
    test "$(readlink "$PI_CODING_AGENT_DIR/AGENTS.md")" = "$HOME/.config/agents/AGENTS.md"
    test "$(cat "$PI_CODING_AGENT_DIR/AGENTS.md")" = 'managed instructions'
    test -L "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md"
    test ! -L "$PI_CODING_AGENT_DIR/skills/writing-well"
    test ! -e "$PI_CODING_AGENT_DIR/skills/tavily-search"
    test -z "$(find "$PI_CODING_AGENT_DIR" -name '.dotfiles-backup.*')"
  done
  export PI_CODING_AGENT_DIR="$HOME/without-browser"
  ${lib.getExe withoutBrowser} --version
  if ${lib.getExe withoutBrowser} browser-prefetch >"$TMPDIR/browser.log" 2>&1; then
    echo 'Browser installation must be disabled' >&2
    exit 1
  fi
  grep -q 'Browser support is disabled' "$TMPDIR/browser.log"
  ${lib.getExe pkgs.python3} - <<'PY'
  import json, os
  from pathlib import Path
  config = json.loads((Path(os.environ["PI_CODING_AGENT_DIR"]) / "mcp.json").read_text())
  assert "playwright-lazy" not in config.get("mcpServers", {})
  PY
  touch "$out"
''
