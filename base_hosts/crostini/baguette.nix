# What only the Baguette image needs, on top of crostini.nix. The LXC
# container does not import this file.
{ lib, pkgs, ... }:
{
  programs.git.package = pkgs.gitMinimal-runtime;

  virtualisation.buildMemorySize = 1024 * 8;
  virtualisation.diskImageSize = 1024 * 16;

  # ChromeOS's log console cannot answer systemd's early terminal query.
  # ManagerEnvironment is read too late. Preserve the host's command line
  # and supply a default through systemd's debugging override before exec.
  # This keeps stock systemd; SYSTEMD_PROC_CMDLINE has no stability guarantee.
  boot.systemdExecutable = lib.mkDefault (
    toString (
      pkgs.writeShellScript "baguette-systemd" ''
        cmdline=$(< /proc/cmdline)
        case " $cmdline " in
          *" systemd.tty.term.console="*|*" TERM="*) ;;
          *) export SYSTEMD_PROC_CMDLINE="$cmdline systemd.tty.term.console=dumb" ;;
        esac
        exec /run/current-system/systemd/lib/systemd/systemd "$@"
      ''
    )
  );

  # The root of the image. The setuid files live in /run/wrappers and the
  # device nodes in /dev, both their own mounts. systemd-remount-fs applies
  # the flags after the kernel mounts the root. The LXC guest gets its root
  # from the host, so this file, not crostini.nix.
  fileSystems."/".options = [
    "nosuid"
    "nodev"
  ];
}
