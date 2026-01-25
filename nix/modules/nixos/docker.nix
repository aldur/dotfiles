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
}
