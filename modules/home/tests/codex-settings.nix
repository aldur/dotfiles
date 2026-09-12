{
  pkgs,
  self,
  inputs,
  system,
}:
let
  evaluate =
    extraModules:
    let
      evaluated = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs.inputs = inputs // { inherit self; };
        modules = [
          self.nixosModules.default
          { programs.aldur.codex.enable = true; }
        ] ++ extraModules;
      };
    in
    evaluated.config.home-manager.users.${evaluated.config.mainUser};

  generic = evaluate [ ];
  crostini = evaluate [ ../../../base_hosts/crostini/crostini.nix ];
  activation = home: pkgs.writeShellScript "activate-codex-settings" ''
    set -euo pipefail
    ${home.home.activation.codexSettings.data}
  '';
in
# Exercise the real activation snippets and their generated TOML, so a host
# setting that evaluates correctly but never reaches config.toml fails here.
assert crostini.programs.codex.writableSettings.tui.whimsy == false;
assert !(generic.programs.codex.writableSettings.tui ? whimsy);
assert !(crostini.programs.codex.writableSettings.tui ? animations);
pkgs.runCommand "codex-settings-migration" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./codex-settings.py} ${activation crostini} ${activation generic}
  touch "$out"
''
