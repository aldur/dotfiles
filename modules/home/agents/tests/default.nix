{
  pkgs,
  lib,
  self,
}:
let
  home = enabled: (self.lib.mkHome {
    system = pkgs.stdenv.hostPlatform.system;
    username = "instructions-check";
    profile = "headless";
    modules = [
      {
        programs.aldur.codex.enable = enabled;
        programs.aldur.claude-code.enable = enabled;
        programs.aldur.lazyvim.enable = false;
        programs.pi.enable = enabled;
      }
      ({ config, lib, pkgs, ... }: {
        # Build the real Home Manager links without unrelated packages.
        home.file = lib.mkForce (import ../default.nix { inherit config lib pkgs; }).config.home.file;
      })
    ];
  }).config;
  enabled = home true;
  disabled = home false;
  source = enabled.home.file.".codex".source;
  claudeSource = enabled.home.file."${enabled.programs.claude-code.configDir}".source;
  closure = pkgs.closureInfo { rootPaths = [ source claudeSource enabled.home-files ]; };
  activation = pkgs.writeShellScript "activate-agent-instructions" ''
    set -euo pipefail
    ${enabled.lib.bash.initHomeManagerLib}
    ${enabled.home.activation.agentInstructions.data}
  '';
  emptyHome = pkgs.runCommand "empty-instructions-home" { } ''mkdir "$out"'';
  entrypoint = pkgs.callPackage ../../../../base_hosts/pi-container/pi-container.nix {
    homeFiles = emptyHome;
    homeProfile = emptyHome;
    piConfigSync = pkgs.writeShellScriptBin "pi-config-sync-fixture" "exit 0";
    resetAgentInstructions = enabled.programs.agent-instructions.reset;
  } 501;
in
assert !(disabled.home.activation ? agentInstructions);
assert !(disabled.home.file ? ".codex");
assert !(disabled.home.file ? ".pi/agent");
assert !(disabled.home.file ? "${disabled.programs.claude-code.configDir}");
assert toString source == toString enabled.home.file.".pi/agent".source;
pkgs.runCommand "agent-instructions-test" { nativeBuildInputs = [ pkgs.gettext ]; } ''
  test "$(readlink ${source}/AGENTS.md)" = /home/instructions-check/.config/agents/AGENTS.md
  test "$(readlink ${claudeSource}/CLAUDE.md)" = /home/instructions-check/.config/agents/AGENTS.md
  for file in .codex/AGENTS.md .claude/CLAUDE.md .pi/agent/AGENTS.md; do
    test "$(readlink ${enabled.home-files}/$file)" = /home/instructions-check/.config/agents/AGENTS.md
  done
  ${lib.getExe pkgs.python3} ${./reset.py} ${activation} ${../AGENTS.md} \
    ${lib.getExe entrypoint} ${pkgs.coreutils}/bin/true ${closure}/store-paths
  touch "$out"
''
