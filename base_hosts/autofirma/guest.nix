# The AutoFirma guest: an XFCE desktop that logs `aldur` in, Firefox, and
# AutoFirma wired to it through the afirma:// protocol handler.
#
# Why a VM at all: AutoFirma talks to the browser over a TLS WebSocket on
# 127.0.0.1 and, to make the browser trust it, installs its own root CA into
# the system trust store. Here that CA lands in /etc/Autofirma and in the
# guest's Firefox only. The host trust store never sees it.
#
# This file holds what runs. VM plumbing (disks, RAM, serial console) lives
# in autofirma.nix so the NixOS test in tests/ can reuse the guest as is.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  user = config.mainUser;

  # autofirma-nix pins the Maven dependency trees as fixed-output
  # derivations. Two of the pinned hashes no longer match what Maven
  # Central serves (probed on 2026-09-02, upstream at ea43f59). Rebuild
  # those two with the hashes observed today. Drop these overrides once
  # upstream refreshes fixed-output-derivations.lock.
  upstream = inputs.autofirma-nix.packages.${system}.autofirma;
  autofirma = upstream.override {
    jmulticard = upstream.clienteafirma.dependencies.jmulticard.override {
      maven-dependencies-hash = "sha256-2lUqrN8s0KTbk8wd76FkU5wgaPZnzmpO9rgTE6Oe+os=";
    };
    maven-dependencies-hash = "sha256-aNtvfZuu84dS3/ZvbuVlmt2ELQFHr0OtNABnDo/Hdp4=";
  };

  # Import a PKCS#12 certificate into every Firefox profile of the user.
  # AutoFirma reads the certificates from the Firefox (NSS) store.
  import-certificate = pkgs.writeShellApplication {
    name = "import-certificate";
    runtimeInputs = [
      pkgs.nss.tools
      pkgs.gnugrep
    ];
    text = ''
      if [ $# -lt 1 ]; then
        echo "usage: import-certificate CERT.p12 [PASSWORD]" >&2
        exit 2
      fi
      cert="$1"
      profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
      if [ ! -f "$profiles_ini" ]; then
        echo "No Firefox profile yet. Start Firefox once, then retry." >&2
        exit 1
      fi
      grep -oP '^Path=\K.*' "$profiles_ini" | while read -r profile; do
        case "$profile" in
          /*) dir="$profile" ;;
          *) dir="$HOME/.mozilla/firefox/$profile" ;;
        esac
        [ -f "$dir/cert9.db" ] || continue
        echo "Importing into $dir"
        if [ $# -ge 2 ]; then
          pk12util -i "$cert" -d "sql:$dir" -W "$2"
        else
          pk12util -i "$cert" -d "sql:$dir"
        fi
      done
      echo "Done. Restart Firefox so it picks the certificate up."
    '';
  };

  startPage = pkgs.writeText "index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>AutoFirma VM</title>
      <style>
        body { font: 16px/1.5 sans-serif; max-width: 42em; margin: 3em auto; padding: 0 1em; }
        code { background: #eee; padding: 0 .3em; }
      </style>
    </head>
    <body>
      <h1>AutoFirma VM</h1>
      <p>AutoFirma and its root certificate live in this VM only.</p>
      <h2>First run</h2>
      <ol>
        <li>Copy your certificate into the VM:
          <code>scp -P 2222 cert.p12 ${user}@localhost:</code></li>
        <li>In a terminal here, run <code>import-certificate cert.p12</code>.</li>
        <li>Restart Firefox.</li>
      </ol>
      <h2>Links</h2>
      <ul>
        <li><a href="https://valide.redsara.es/valide/">VALIDe</a>: check a signature or test the setup.</li>
        <li><a href="https://sede.administracion.gob.es/carpeta/">Carpeta Ciudadana</a></li>
        <li><a href="https://sede.agenciatributaria.gob.es/">Agencia Tributaria</a></li>
        <li><a href="https://sede.seg-social.gob.es/">Seguridad Social</a></li>
        <li><a href="https://sede.dgt.gob.es/">DGT</a></li>
        <li><a href="https://www.sede.fnmt.gob.es/">FNMT</a></li>
      </ul>
    </body>
    </html>
  '';
in
{
  imports = [ inputs.autofirma-nix.nixosModules.autofirma ];

  networking.hostName = "autofirma-vm";

  # -- AutoFirma + Firefox --------------------------------------------------

  programs.autofirma = {
    enable = true;
    package = autofirma;
    # Generates the local CA in /etc/Autofirma and makes Firefox trust it.
    firefoxIntegration.enable = true;
  };

  # The module's oneshot writes the WebSocket keystore as root with mode
  # 0600. AutoFirma runs as the user, cannot read it, and every socket
  # attempt fails with SAF_45. Its password is fixed upstream ("654321"),
  # so world-readable loses nothing. Upstream's tests run as root and miss
  # this.
  systemd.services.create-autofirma-cert.serviceConfig.ExecStartPost =
    "${pkgs.coreutils}/bin/chmod 0644 /etc/Autofirma/autofirma.pfx";

  programs.firefox = {
    enable = true;
    autoConfig = ''
      pref("network.protocol-handler.expose.afirma", true);
      // No "Allow this site to open afirma links?" prompt. AutoScript
      // polls AutoFirma for a short while after the click; a missed
      // prompt fails the signature. AutoFirma is the only external
      // handler in this guest.
      pref("security.external_protocol_requires_permission", false);
    '';
    policies = {
      # Hand afirma:// to the desktop entry, no application chooser.
      Handlers.schemes.afirma = {
        action = "useSystemDefault";
        ask = false;
      };
      DisableAppUpdate = true;
      DisableTelemetry = true;
      Homepage = {
        StartPage = "homepage";
        URL = "file:///etc/autofirma-vm/index.html";
      };
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
    };
  };

  environment.etc."autofirma-vm/index.html".source = startPage;

  # Open Firefox with the session; the VM exists for it.
  environment.etc."xdg/autostart/autofirma-vm-firefox.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Firefox
    Exec=firefox
    OnlyShowIn=XFCE;
  '';

  environment.systemPackages = [
    import-certificate
    pkgs.nss.tools
  ];

  # Firefox 154 puts new profiles under ~/.config/mozilla. AutoFirma only
  # looks in ~/.mozilla/firefox/profiles.ini on Linux, so keep the legacy
  # location or it finds no certificates.
  environment.sessionVariables.MOZ_LEGACY_HOME = "1";

  # -- Desktop --------------------------------------------------------------

  services.xserver = {
    enable = true;
    desktopManager.xfce = {
      enable = true;
      enableScreensaver = false;
    };
    displayManager.lightdm.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    inherit user;
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
  ];

  # -- User -----------------------------------------------------------------

  users.users.${user}.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;
  security.sudo-rs.wheelNeedsPassword = false;

  # Serial console login for debugging; the desktop is on the display.
  services.getty.autologinUser = user;

  # The base config ships a large CLI toolbox. Keep the editor out: this
  # guest is a browser kiosk, not a workstation.
  programs.aldur.lazyvim.enable = lib.mkDefault false;
}
