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
      # SSH host keys via symlink, NOT the default bind-mount. sshd-keygen
      # does `rm -f $key` unless the path is a symlink; on a bind-mounted
      # (empty) file the rm fails with EBUSY under `set -e`, so no key is
      # ever generated and sshd starts without host keys. With a dangling
      # symlink the rm is skipped and `ssh-keygen -f` writes through it
      # into /persist (parent dir created by configureParent). Same shape
      # as the upstream preservation example. File modes are set by
      # ssh-keygen itself (0600 / 0644).
      {
        file = "/etc/ssh/ssh_host_ed25519_key";
        how = "symlink";
        configureParent = true;
      }
      {
        file = "/etc/ssh/ssh_host_ed25519_key.pub";
        how = "symlink";
        configureParent = true;
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
