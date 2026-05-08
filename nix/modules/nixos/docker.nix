{
  virtualisation.docker = {
    rootless = {
      enable = true;
      setSocketVariable = true;

      # Stop Docker from messing with iptables
      daemon.settings.iptables = false;
      daemon.settings.ip6tables = false;
    };
  };

  # Rootless Docker needs newuidmap/newgidmap for user-namespace mapping and
  # fusermount{,3} for the fuse-overlayfs storage driver. These plain
  # assignments override hardening.minimizeWrappers' mkDefault values.
  security.wrappers = {
    newuidmap.setuid = true;
    newgidmap.setuid = true;
    fusermount.enable = true;
    fusermount3.enable = true;
  };
}
