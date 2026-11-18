{
  pkgs,
  self,
  inputs,
  pi,
}:
let
  inherit (pkgs) lib;
  home = self.lib.mkHome {
    system = pkgs.stdenv.hostPlatform.system;
    profile = "headless";
    modules = [
      {
        programs.aldur.lazyvim.enable = false;
        programs.pi.enable = true;
      }
    ];
  };
  files = lib.filter (file: lib.hasPrefix ".pi/agent" file.target) (
    lib.attrValues home.config.home.file
  );
  skills = lib.filter (file: lib.hasPrefix ".pi/agent/skills/" file.target) files;
  # Lay out the Pi files as Home Manager does in a generation.
  homeFiles = pkgs.runCommand "home-manager-files" { nativeBuildInputs = [ pkgs.lndir ]; } (
    lib.concatMapStrings (file: ''
      target=$out/${lib.escapeShellArg file.target}
      mkdir -p "$(dirname "$target")"
      if [ -d ${file.source} ] && ${lib.boolToString file.recursive}; then
        mkdir -p "$target" && lndir -silent ${file.source} "$target"
      else
        ln -s ${file.source} "$target"
      fi
    '') files
  );
  generation = pkgs.runCommand "home-manager-generation" { } ''
    mkdir "$out"
    ln -s ${homeFiles} "$out/home-files"
  '';
  activation = pkgs.writeShellScript "pi-home-activation" ''
    set -e
    ${home.config.lib.bash.initHomeManagerLib}
    ${lib.concatMapStringsSep "\n" (entry: entry.data) (
      builtins.filter (
        entry:
        builtins.elem entry.name [
          "piStandaloneLinks"
          "checkLinkTargets"
          "linkGeneration"
          "agentInstructions"
        ]
      ) (inputs.home-manager.lib.hm.dag.topoSort home.config.home.activation).result
    )}
  '';
in
assert skills != [ ];
pkgs.runCommand "pi-home-skills-test" { nativeBuildInputs = [ pkgs.gettext ]; } ''
  export HOME=$TMPDIR/home PNPM_HOME=$TMPDIR/pnpm
  mkdir -m 700 "$HOME"

  # The standalone launcher runs first and links its files into the store.
  ${lib.getExe pi} --version
  test "$(readlink "$HOME/.pi/agent/AGENTS.md")" = ${../../../modules/home/agents/AGENTS.md}
  test -L "$HOME/.pi/agent/skills/writing-well"

  # Edited instructions differ from the launcher's copy.
  mkdir -p "$HOME/.config/agents"
  echo edited > "$HOME/.config/agents/AGENTS.md"

  export newGenPath=${generation}
  ${activation}
  oldGenPath=${generation} ${activation}
  test "$(readlink "$HOME/.pi/agent/AGENTS.md")" = ${homeFiles}/.pi/agent/AGENTS.md
  ${lib.concatMapStrings (file: ''
    test -d "$HOME"/${lib.escapeShellArg file.target}
    test ! -L "$HOME"/${lib.escapeShellArg file.target}
    cmp "$HOME"/${lib.escapeShellArg file.target}/SKILL.md ${file.source}/SKILL.md
  '') skills}
  touch "$out"
''
