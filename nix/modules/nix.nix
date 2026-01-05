{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  name = "determinate-nix";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = lib.mkEnableOption "Enable Determinate Nix (without FlakeHub)";
  };

  config = lib.mkMerge [
    {
      nix = {
        settings = {
          experimental-features = "nix-command flakes";
        };

        package = pkgs.nixVersions.latest;

        optimise = {
          automatic = true;
        };
      };
    }

    # Pin nixpkgs to the flake input.
    (
      let
        inherit (pkgs.stdenv) isDarwin;

        # `nix-darwin` 25.11+ does this automatically via nixpkgs.flake.setFlakeRegistry,
        # so we only set it manually on Linux or if that option is disabled.
        darwinFlakeRegistryDisabled =
          isDarwin
          && config ? nixpkgs
          && config.nixpkgs ? flake
          && config.nixpkgs.flake ? setFlakeRegistry
          && !config.nixpkgs.flake.setFlakeRegistry;
        shouldSetRegistry = pkgs.stdenv.isLinux || darwinFlakeRegistryDisabled;
      in
      lib.mkIf shouldSetRegistry {
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
        warnings = lib.optionals darwinFlakeRegistryDisabled [
          "nixpkgs.flake.setFlakeRegistry is disabled; falling back to manual nix.registry.nixpkgs configuration from dotfiles."
        ];
      }
    )

    (lib.mkIf cfg.enable {
      nix.package = lib.mkForce inputs.detnix.packages."${pkgs.stdenv.hostPlatform.system}".default;
      # https://docs.determinate.systems/guides/telemetry
      environment.variables = {
        DETSYS_IDS_TELEMETRY = "disabled";
      };
    })
  ];
}
