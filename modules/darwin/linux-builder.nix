{ inputs, config, lib, pkgs, ... }:
# Hosts opt into either builder. Bootstrap Rosetta with the standard builder
# first, then disable nix.linux-builder and enable services.linux-builder.
let
  name = "linux-builder";
  cfg = config.services.${name};
  standardBuilder = config.nix.linux-builder;
  vm = standardBuilder.package.nixosConfig.virtualisation;

  growDisk = pkgs.writeShellScript "grow-linux-builder-disk" ''
    set -euo pipefail
    image=${lib.escapeShellArg vm.diskImage}
    if [[ -f "$image" ]]; then
      # Do not bypass QEMU's image locks: an active VM must stop first.
      size=$(${lib.getExe' vm.qemu.package "qemu-img"} info --output=json "$image" |
        ${lib.getExe pkgs.jq} -er '."virtual-size"')
      if (( size < ${toString (vm.diskSize * 1024 * 1024)} )); then
        ${lib.getExe' vm.qemu.package "qemu-img"} resize "$image" ${toString vm.diskSize}M
      fi
    fi
  '';

  # https://discourse.nixos.org/t/mkif-vs-if-then/28521/4
  mkIfElse = with lib; (p: yes: no: mkMerge [ (mkIf p yes) (mkIf (!p) no) ]);
in {
  imports = [ inputs.nix-rosetta-builder.darwinModules.default ];

  options.services.${name} = { enable = lib.mkEnableOption "Linux builder"; };

  config = lib.mkMerge [
    {
      nix.linux-builder = {
        enable = lib.mkDefault false;
        maxJobs = lib.mkDefault 2;
        config = { config, lib, ... }: {
          virtualisation = {
            cores = lib.mkDefault 4;
            darwin-builder.memorySize = lib.mkDefault (8 * 1024);
            darwin-builder.diskSize = lib.mkDefault (64 * 1024);
            qemu.forceAccel = lib.mkDefault true;
            fileSystems."/".autoResize = lib.mkDefault true;

            # Replace the default SSH forward so it only listens on this Mac.
            forwardPorts = lib.mkForce [
              {
                from = "host";
                host.address = "127.0.0.1";
                host.port = config.virtualisation.darwin-builder.hostPort;
                guest.port = 22;
              }
            ];
          };
        };
      };
    }
    (lib.mkIf (standardBuilder.enable && vm.diskImage != null) {
      # launchd stops the previous VM before starting this job. Grow existing
      # images here; new images are created at diskSize by the normal launcher.
      launchd.daemons.linux-builder.script = lib.mkBefore ''
        ${growDisk} || exit $?
      '';
    })
    (mkIfElse cfg.enable { nix-rosetta-builder.onDemand = true; } {
      # The upstream Rosetta module defaults to enabled; hosts must opt in.
      nix-rosetta-builder.enable = false;
    })
  ];
}
