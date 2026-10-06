# The same browser in the existing QEMU launcher, with AutoFirma's minimal
# XFCE session. Persistent storage and browser policy live in guest.nix.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./guest.nix
  ];
  # The development guest's flake-copy helper needs Home Manager.
  disabledModules = [ "${inputs.self}/modules/current_system_flake.nix" ];

  networking.hostName = "browser-vm";
  virtualisation = {
    graphics = true;
    writableStoreUseTmpfs = false;
  };
  hardware.graphics.enable = true;

  environment = {
    etc."xdg/autostart/firefox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Firefox
      Exec=${lib.getExe config.programs.firefox.finalPackage}
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
    spice-vdagentd.enable = true;
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
