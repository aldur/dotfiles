{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    "${inputs.self}/base_hosts/appliance/qemu.nix"
    ./guest.nix
  ];
  networking.hostName = "signal-vm";
  # Cage uses pixman. Signal disables GPU access. Neither requires hardware GL drivers.
  hardware.graphics.enable = lib.mkForce false;
  services.cage = {
    enable = true;
    user = config.mainUser;
    package = pkgs.cage.override {
      wlroots_0_20 = pkgs.wlroots_0_20.override { enableXWayland = false; };
    };
    environment = {
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "cage";
      GDK_BACKEND = "wayland";
      GSK_RENDERER = "cairo";
      WLR_RENDERER = "pixman";
    };
    program = pkgs.writeShellScript "signal-session" ''
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      while true; do
        ${lib.getExe config.aldur.appliance.application} || true
        sleep 1
      done
    '';
  };
  # GNOME Keyring treats an inherited capability as permission to keep IPC_LOCK.
  security.pam.services.cage.rules.session.systemd.settings.default-capability-ambient-set = "";
  systemd.services.cage-tty1 = {
    after = [ "firewall.service" ];
    serviceConfig = {
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      NoNewPrivileges = true;
      LimitMEMLOCK = "64M";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
