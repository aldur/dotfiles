# Check our guest policy with the real platform modules, without booting a VM.
{
  lib,
  runCommand,
  baguette,
  lxc,
}:
let
  c = baguette.config;
  sessionOrdering =
    configuration:
    let
      cfg = configuration.config;
      user = cfg.mainUser;
      manager = cfg.systemd.services."user@${toString cfg.users.users.${user}.uid}";
    in
    !manager.restartIfChanged
    && lib.elem "home-manager-${user}.service" manager.after
    && lib.elem "home-manager-${user}.service" manager.wants;
in
assert lib.all sessionOrdering [
  baguette
  lxc
];
assert c.nix.settings.max-jobs == 1 && c.nix.settings.cores == 2;
assert c.systemd.services.nix-daemon.serviceConfig.MemoryHigh == "60%";
assert c.systemd.services.nix-daemon.serviceConfig.MemoryMax == "70%";
# The Baguette VM's memory budget must not leak into the LXC guest.
assert !(lxc.config.systemd.services.nix-daemon.serviceConfig ? MemoryMax);
runCommand "crostini-rebuild-resources" { } "touch $out"
