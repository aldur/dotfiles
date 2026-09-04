# The guest side of `qemu-vm --file NAME=PATH`. QEMU exposes the host files
# through fw_cfg. sysfs shows them to root only. This service copies them
# for the user to /run/qemu-vm-files at boot.
{ config, ... }:
let
  filesDir = "/run/qemu-vm-files";
in
{
  boot.kernelModules = [ "qemu_fw_cfg" ];

  systemd.services.qemu-vm-files = {
    description = "Copy the files from `qemu-vm --file` to ${filesDir}";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    unitConfig.ConditionPathIsDirectory = "/sys/firmware/qemu_fw_cfg/by_name/opt/qemu-vm";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 0700 -o ${config.mainUser} ${filesDir}
      for dir in /sys/firmware/qemu_fw_cfg/by_name/opt/qemu-vm/*/; do
        name=$(basename "$dir")
        install -m 0400 -o ${config.mainUser} "$dir/raw" "${filesDir}/$name"
      done
    '';
  };
}
