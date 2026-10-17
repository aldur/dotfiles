{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./qemu.nix ];

  environment = {
    etc."xdg/autostart/appliance.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=${config.aldur.appliance.application.meta.description or "Application"}
      Exec=${lib.getExe config.aldur.appliance.application}
      OnlyShowIn=XFCE;
    '';
    xfce.excludePackages = with pkgs; [
      mousepad
      parole
      pavucontrol
      ristretto
      xfce4-appfinder
      xfce4-screenshooter
      xfce4-taskmanager
      xdg-desktop-portal-xapp
    ];
  };

  services = {
    gvfs.enable = lib.mkForce false;
    tumbler.enable = lib.mkForce false;
    # Available only when the launcher is given --clipboard.
    spice-vdagentd.enable = lib.mkDefault false;
    xserver = {
      enable = true;
      desktopManager.xfce = {
        enable = true;
        enableScreensaver = false;
      };
      displayManager.lightdm.enable = true;
    };
    displayManager.autoLogin = {
      enable = true;
      user = config.mainUser;
    };
  };
}
