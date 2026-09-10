{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.programs.macos-vm;
in
{
  options.programs.macos-vm = {
    enable = lib.mkEnableOption "macOS VM launcher using Tart on Apple Silicon";
    defaultVmDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/macos-vm";
      description = "Directory for macOS VM state and downloaded images";
    };
    defaultMemory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = "Memory size in MB";
    };
    defaultCores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of CPU cores";
    };
    defaultDiskSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 64;
      description = "Minimum virtual disk size in GB";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
        message = "programs.macos-vm requires an Apple Silicon Mac (aarch64-darwin).";
      }
    ];
    home.packages = [
      (pkgs.callPackage ../../packages/macos-vm/macos-vm.nix {
        inherit inputs;
        inherit (cfg)
          defaultVmDir
          defaultMemory
          defaultCores
          defaultDiskSize
          ;
      })
    ];
  };
}
