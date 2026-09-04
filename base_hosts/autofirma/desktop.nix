# The QEMU session of the guest: an XFCE desktop with auto-login, Firefox
# at start, and the clipboard agent. The files of `qemu-vm --file` come in
# through fw_cfg (modules/nixos/qemu-vm-files.nix).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;
in
{
  imports = [ ./guest.nix ];

  networking.hostName = "autofirma-vm";

  aldur.autofirma = {
    filesDir = "/run/qemu-vm-files";
    filesHelp = ''
      <ol>
        <li>Stop the VM. Start it again with your certificate:
          <code>autofirma-vm --gui --file cert.p12=/path/to/cert.p12</code></li>
        <li>Type the certificate password in the dialog that opens.</li>
      </ol>
      <p>Or copy the file over SSH. The guest sshd has no SFTP, so
        <code>scp</code> does not work:
        <code>cat cert.p12 | ssh -p 2222 ${user}@localhost "cat - &gt; cert.p12"</code></p>
    '';
  };

  programs = {
    # -- Size -----------------------------------------------------------------
    # Removes the interactive tools of the shared home config.
    aldur.workstation.enable = false;

    # Keep the editor out. This guest is a browser appliance.
    aldur.lazyvim.enable = lib.mkDefault false;
  };

  environment = {
    # Start Firefox with the session.
    etc."xdg/autostart/autofirma-vm-firefox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Firefox
      Exec=/run/current-system/sw/bin/autofirma-vm-firefox
      OnlyShowIn=XFCE;
    '';

    # For clipboard checks by hand; see the README.
    systemPackages = [ pkgs.xclip ];

    # XFCE programs this guest does not use. The xapp portal alone pulls the
    # MATE panel and libmateweather.
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
    # Virtual filesystems and thumbnails pull samba, GNOME online accounts,
    # and webkitgtk. Thunar works without them.
    gvfs.enable = lib.mkForce false;
    tumbler.enable = lib.mkForce false;

    # Clipboard sharing with the host. The agent needs the virtio serial
    # port that `qemu-vm --clipboard` adds. Without it, it exits.
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
      inherit user;
    };
  };
}
