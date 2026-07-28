{
  writeText,
  # This flake, for the NixOS modules it exports, and the inputs those modules
  # are given as `specialArgs`.
  self,
  inputs,
  system,
}:

# Evaluates a NixOS system carrying nothing but this repo's own defaults, so a
# module that only holds together thanks to a host's configuration still fails
# here. Only the derivation path is written out: the system is never built, let
# alone booted.

let
  headless = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inputs = inputs // {
        inherit self;
      };
    };
    modules = [
      self.nixosModules.default
      (
        { modulesPath, ... }:
        {
          imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
          networking.hostName = "headless";
          # This system is only evaluated, never booted
          users.allowNoPasswordLogin = true;
        }
      )
    ];
  };
in

writeText "headless-defaults-toplevel" (
  builtins.unsafeDiscardStringContext headless.config.system.build.toplevel.drvPath
)
