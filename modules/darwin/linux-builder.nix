{ inputs, config, lib, ... }:
# An existing Linux builder is needed to initially bootstrap `nix-rosetta-builder`.
# If one isn't already available: comment out the `nix-rosetta-builder` module below,
# uncomment this `linux-builder` module, and run `darwin-rebuild switch`:
# { nix.linux-builder.enable = true; }
# Then: uncomment `nix-rosetta-builder`, remove `linux-builder`, and `darwin-rebuild switch`
# a second time. Subsequently, `nix-rosetta-builder` can rebuild itself.
let
  name = "linux-builder";
  cfg = config.services.${name};

  # https://discourse.nixos.org/t/mkif-vs-if-then/28521/4
  mkIfElse = with lib; (p: yes: no: mkMerge [ (mkIf p yes) (mkIf (!p) no) ]);
in {
  imports = [ inputs.nix-rosetta-builder.darwinModules.default ];

  options.services.${name} = { enable = lib.mkEnableOption "Linux builder"; };

  config = mkIfElse cfg.enable { nix-rosetta-builder.onDemand = true; } {
    # This is required because the module defaults to being enabled.
    # https://github.com/cpick/nix-rosetta-builder/blob/ebb7162a975074fb570a2c3ac02bc543ff2e9df4/module.nix#L31
    nix-rosetta-builder.enable = false;
  };
}
