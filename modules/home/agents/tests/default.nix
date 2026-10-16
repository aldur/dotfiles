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
    modules = [{
      programs.aldur.codex.enable = enabled;
      programs.aldur.claude-code.enable = enabled;
      programs.aldur.lazyvim.enable = false;
      programs.pi.enable = enabled;
    }];
  }).config;
  enabled = home true;
  disabled = home false;
  source = enabled.home.file.".codex/AGENTS.md".source;
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
assert !(disabled.home.file ? ".codex/AGENTS.md");
assert !(disabled.home.file ? ".pi/agent/AGENTS.md");
assert !(disabled.home.file ? "${disabled.programs.claude-code.configDir}/CLAUDE.md");
assert toString source == toString enabled.home.file.".pi/agent/AGENTS.md".source;
assert toString source == toString enabled.home.file."${enabled.programs.claude-code.configDir}/CLAUDE.md".source;
pkgs.runCommand "agent-instructions-test" { nativeBuildInputs = [ pkgs.gettext ]; } ''
  test "$(readlink ${source})" = /home/instructions-check/.config/agents/AGENTS.md
  ${lib.getExe pkgs.python3} ${./reset.py} ${activation} ${../AGENTS.md} \
    ${lib.getExe entrypoint} ${pkgs.coreutils}/bin/true
  touch "$out"
''
