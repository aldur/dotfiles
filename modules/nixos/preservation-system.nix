{
  config,
  lib,
  ...
}:
let
  cfg = config.aldur.preservation-system;
in
{
  options.aldur.preservation-system = {
    enable = lib.mkEnableOption "system-level preservation (machine-id + SSH host keys)";
  };

  config = lib.mkIf cfg.enable {
    preservation.preserveAt."/persist".files = [
      # machine-id must be populated before systemd starts, otherwise
      # journald + DBus generate a fresh one every boot.
      {
        file = "/etc/machine-id";
        inInitrd = true;
        mode = "0444";
      }
      # SSH host keys via default bind-mount. On fresh deploy
      # /persist/etc/ssh/... doesn't exist yet — preservation creates
      # empty files, sshd-keygen fills them on first boot (writes go
      # through the bind to /persist), and subsequent boots find the
      # populated keys.
      {
        file = "/etc/ssh/ssh_host_ed25519_key";
        configureParent = true;
        mode = "0600";
      }
      {
        file = "/etc/ssh/ssh_host_ed25519_key.pub";
        configureParent = true;
        mode = "0644";
      }
    ];

    # `systemd-machine-id-commit` writes /run/machine-id to /etc; with
    # /etc/machine-id bind-mounted from /persist (inInitrd above) it's
    # already authoritative, and the commit would just fail noisily.
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    # NOTE: when /persist is a NixOS fileSystems entry (e.g. its own
    # btrfs subvolume on bee), the host must set
    #   fileSystems."/persist".neededForBoot = true;
    # otherwise preservation's inInitrd files write to the ephemeral
    # rootfs at /sysroot/persist instead of the persist mount. Set
    # per-host because crostini's /persist comes from the LXC host
    # and isn't a NixOS fileSystems entry at all.
  };
}
