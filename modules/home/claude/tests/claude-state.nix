{
  pkgs,
  self,
  inputs,
}:
let
  home = self.lib.mkHome {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      {
        programs.aldur = {
          workstation.enable = false;
          lazyvim.enable = false;
          claude-code.enable = true;
        };
      }
    ];
  };
  # Execute the real settings and file-linking steps in Home Manager's order.
  # A small generation fixture avoids activating unrelated services/packages.
  activation = pkgs.writeShellScript "claude-activation-test" ''
    set -e
    ${home.config.lib.bash.initHomeManagerLib}
    ${pkgs.lib.concatMapStringsSep "\n" (entry: entry.data) (
      builtins.filter (
        entry:
        builtins.elem entry.name [
          "claudeSettings"
          "linkGeneration"
        ]
      ) (inputs.home-manager.lib.hm.dag.topoSort home.config.home.activation).result
    )}
  '';
in
pkgs.runCommand "claude-state-test" { nativeBuildInputs = [ pkgs.gettext ]; } ''
  ${pkgs.python3}/bin/python3 ${./claude-state.py} ${../claude-state.py} ${pkgs.jq}/bin/jq
  ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
    export HOME=$TMPDIR/home
    mkdir -m 700 "$HOME"
    export newGenPath=$TMPDIR/generation
    mkdir -p "$newGenPath/home-files/.claude/skills/fixture"
    echo fixture > "$newGenPath/home-files/.claude/skills/fixture/SKILL.md"

    # Ubuntu's user-private-group defaults expose the activation ordering bug.
    umask 0002
    ${activation}
    test "$(stat -c %a "$HOME/.claude")" = 700
    test "$(stat -c %a "$HOME/.claude/settings.json")" = 600
    test -L "$HOME/.claude/skills/fixture/SKILL.md"
    ${pkgs.jq}/bin/jq -e '.theme == "dark"' "$HOME/.claude/settings.json"
    ${activation}

    # Dry runs must not create state or skill links in an empty home.
    export HOME=$TMPDIR/dry-home
    mkdir -m 700 "$HOME"
    DRY_RUN=1 ${activation}
    test ! -e "$HOME/.claude"
    test ! -e "$HOME/.claude.json"
    umask 0022
  ''}
  touch "$out"
''
