# What only the Baguette image needs, on top of crostini.nix. The LXC
# container does not import this file.
{ ... }:
{
  virtualisation.buildMemorySize = 1024 * 8;
  virtualisation.diskImageSize = 1024 * 16;

  # The root of the image. The setuid files live in /run/wrappers and the
  # device nodes in /dev, both their own mounts. systemd-remount-fs applies
  # the flags after the kernel mounts the root. The LXC guest gets its root
  # from the host, so this file, not crostini.nix.
  fileSystems."/".options = [
    "nosuid"
    "nodev"
  ];
}
