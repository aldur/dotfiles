# Browser policy, persistent state and hardening shared by both platforms.
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

  networking.firewall.enable = lib.mkForce true;
  system.stateVersion = "26.05";

  programs = {
    firefox = {
      enable = true;
      wrapperConfig.speechSynthesisSupport = false;
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisableFirefoxAccounts = true;
        OfferToSaveLogins = false;
        PasswordManagerEnabled = false;
        DontCheckDefaultBrowser = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        ExtensionSettings."*".installation_mode = "blocked";
      };
    };
    bash.shellInit = "umask 077";
    fish.enable = lib.mkForce false;
  };
  environment.sessionVariables.MOZ_CRASHREPORTER_DISABLE = "1";

  # Keep web links in this browser.
  xdg.mime.defaultApplications = lib.genAttrs [
    "text/html"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/about"
    "x-scheme-handler/unknown"
  ] (_: lib.mkForce "firefox.desktop");

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
  };
  nix.settings.allowed-users = [ "root" ];

  services = {
    userborn.enable = true;
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
    suppressedSystemUnits = [ "systemd-importd.service" ];
    settings.Manager.DefaultLimitCORE = "0:0";
    user.extraConfig = "DefaultLimitCORE=0:0";
  };

  # /home stays on the persistent root disk: the whole VM is the backup
  # unit. Only temporary files and logs are volatile (as in AutoFirma).
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

  # Use the same size cuts as AutoFirma, retaining Firefox's media codecs
  # and the default fonts (including emoji) for general browsing.
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };
  system.tools.nixos-rebuild.enable = false;
  documentation.enable = false;
  documentation.man.enable = false;
  services.speechd.enable = lib.mkForce false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
