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
  inherit (inputs) self;

  vmScript = pkgs.callPackage ../../packages/qemu-vm/qemu-vm.nix {
    inherit inputs;
    defaultVmDir = cfg.defaultVmDir;
    defaultMemory = cfg.defaultMemory;
    defaultCores = cfg.defaultCores;
    defaultDiskSize = cfg.defaultDiskSize;
    vmFlakeRef = cfg.vmFlakeRef;
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

    vmFlakeRef = mkOption {
      type = types.str;
      default = "path:${builtins.dirOf self.outPath}/base_hosts/qemu";
      description = "Flake reference to the QEMU base host flake";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ vmScript ];
  };
}
