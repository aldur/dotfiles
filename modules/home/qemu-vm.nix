{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.programs.qemu-vm;

  vmScript = pkgs.callPackage ../../packages/qemu-vm/qemu-vm.nix {
    inherit inputs;
    inherit (cfg) defaultVmDir;
    inherit (cfg) defaultMemory;
    inherit (cfg) defaultCores;
    inherit (cfg) defaultDiskSize;
  };

in
{
  options.programs.qemu-vm = {
    enable = mkEnableOption "QEMU VM spawner for base host configuration";

    defaultVmDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/qemu-vm";
      description = "Default directory for VM disk images and state";
    };

    defaultMemory = mkOption {
      type = types.int;
      default = 1024 * 16;
      description = "Default memory size in MB";
    };

    defaultCores = mkOption {
      type = types.int;
      default = 8;
      description = "Default number of CPU cores";
    };

    defaultDiskSize = mkOption {
      type = types.int;
      default = 64;
      description = "Default disk size in GB";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ vmScript ];
  };
}
