{
  config,
  inputs,
  options,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;
  fileSystems = {
    "/".options = [
      "nosuid"
      "nodev"
    ];
    "/var/tmp" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "size=1G"
        "mode=1777"
        "nosuid"
        "nodev"
      ];
    };
    "/var/log" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "size=64M"
        "mode=755"
        "nosuid"
        "nodev"
      ];
    };
  };
in
{
  imports = [
    "${inputs.self}/modules/shared/options.nix"
    "${inputs.self}/modules/nixos/users.nix"
    inputs.self.nixosModules.hardening
  ];

  options.aldur.appliance.application = lib.mkOption {
    type = lib.types.package;
    description = "The application started by the appliance desktop.";
  };

  config = {
    networking.firewall.enable = lib.mkForce true;
    environment.defaultPackages = [ ];
    boot.kexec.enable = false;
    system.nssModules = lib.mkForce [ ];
    system.stateVersion = "26.05";

    programs = {
      bash.shellInit = "umask 077";
      fish.enable = lib.mkForce false;
      nano.enable = false;
    };
    users = {
      users.${user} = {
        shell = lib.mkForce pkgs.bashInteractive;
        extraGroups = lib.mkForce [
          "video"
          "render"
        ];
      };
      users.root.hashedPassword = lib.mkForce "!";
      allowNoPasswordLogin = true; # The host controls access to the VM.
    };
    security = {
      sudo.enable = false;
      sudo-rs.enable = false;
      doas.enable = false;
      polkit.enable = lib.mkForce false;
      pam.services.su.requireWheel = true;
      pam.enableUMask = true;
      wrappers =
        lib.genAttrs [ "mount" "umount" "newgrp" "newuidmap" "newgidmap" ] (_: {
          enable = false;
        })
        // {
          # PAM account checks still call this helper from root-started sessions.
          unix_chkpwd.setuid = lib.mkForce false;
        };
    };
    nix.enable = false;

    services = {
      userborn.enable = true;
      openssh.enable = lib.mkForce false;
      avahi.enable = lib.mkForce false;
      printing.enable = lib.mkForce false;
      spice-vdagentd.enable = lib.mkForce false;
      logrotate.enable = false;
      nscd.enable = false;
      # maitred may add the account to `disk` on startup. Group membership
      # must not grant raw access to this VM's session data or system image.
      udev.extraRules = ''
        SUBSYSTEM=="block", OWNER:="root", GROUP:="root", MODE:="0600"
      '';
      journald.storage = "volatile";
      journald.extraConfig = lib.mkForce ''
        RuntimeMaxUse=32M
        ForwardToConsole=no
        ForwardToKMsg=no
        ForwardToSyslog=no
        ForwardToWall=no
      '';
    };
    systemd = {
      oomd.enable = false;
      suppressedSystemUnits = [ "systemd-importd.service" ];
      settings.Manager.DefaultLimitCORE = "0:0";
      user.extraConfig = "DefaultLimitCORE=0:0";
    };

    swapDevices = lib.mkForce [ ];
    zramSwap.enable = false;
    boot.tmp = {
      useTmpfs = true;
      tmpfsSize = "1G";
    };
    inherit fileSystems;
    # qemu-vm replaces fileSystems with virtualisation.fileSystems. Supply
    # the same mounts there when that option exists; Baguette uses them directly.
    virtualisation = lib.optionalAttrs (options.virtualisation ? fileSystems) {
      inherit fileSystems;
    };

    nixpkgs.flake = {
      setFlakeRegistry = false;
      setNixPath = false;
    };
    system.tools.nixos-rebuild.enable = false;
    documentation.enable = false;
    documentation.man.enable = false;
    services.speechd.enable = lib.mkForce false;
    i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
  };
}
