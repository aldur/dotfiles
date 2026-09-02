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

  upstream = inputs.autofirma-nix.packages.${system}.autofirma;

  # You'll need to change this if Maven in nixpkgs changes.
  mavenHashes = {
    jmulticard = upstream.clienteafirma.dependencies.jmulticard.override {
      maven-dependencies-hash = "sha256-xqzFxC+AT5NEEnTxKbNckwTBllMo0Glluuz5GtJLfgg=";
    };
    clienteafirma-external = upstream.clienteafirma.dependencies.clienteafirma-external.override {
      maven-dependencies-hash = "sha256-JxbIpnHG0PEzEw3xEbZhxEoDOBGrVvawoFXpajgLmOw=";
    };
    maven-dependencies-hash = "sha256-5nnqmv8v4QlTlyuckb4x/rWJoSu5b3SyeIiOlxSOvXU=";
  };

  # A size trim, like the "Size" section below. buildFHSEnv puts the full
  # glibc locale archive (220 MiB) in the sandbox. The trimmed archive of
  # the guest is sufficient. The inner buildFHSEnv.nix takes the archive
  # from its `pkgs` argument. This `callPackage` wrapper replaces that
  # argument.
  buildFHSEnvSmallLocales = pkgs.buildFHSEnv.override {
    callPackage =
      path: args:
      pkgs.callPackage path (
        args
        // lib.optionalAttrs ((lib.functionArgs (import path)) ? pkgs) {
          pkgs = pkgs // {
            glibcLocales = config.i18n.glibcLocales;
          };
        }
      );
  };

  autofirma = upstream.override (mavenHashes // { buildFHSEnv = buildFHSEnvSmallLocales; });

  # Imports a PKCS#12 certificate into each Firefox profile of the user.
  # AutoFirma reads the certificates from the Firefox (NSS) store. With no
  # password file, pk12util asks on the terminal.
  import-certificate = pkgs.writeShellApplication {
    name = "import-certificate";
    runtimeInputs = [
      pkgs.nss.tools
      pkgs.gnugrep
    ];
    text = ''
      if [ $# -lt 1 ]; then
        echo "usage: import-certificate CERT.p12 [PASSWORD-FILE]" >&2
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
          pk12util -i "$cert" -d "sql:$dir" -w "$2"
        else
          pk12util -i "$cert" -d "sql:$dir"
        fi
      done
      echo "Done. Restart Firefox so it picks the certificate up."
    '';
  };

  # Starts Firefox for the session. On a fresh profile, it first imports
  # the certificate that `qemu-vm --file cert.p12=…` passed in. The
  # password comes from `cert.password` if passed, else from a dialog.
  # The password only touches a private file in /run/user.
  firefox-session = pkgs.writeShellApplication {
    name = "autofirma-vm-firefox";
    runtimeInputs = [
      config.programs.firefox.finalPackage
      import-certificate
      pkgs.nss.tools
      pkgs.zenity
      pkgs.gnugrep
    ];
    text = ''
      cert=/run/qemu-vm-files/cert.p12
      profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
      if [ -r "$cert" ] && [ ! -f "$profiles_ini" ]; then
        firefox --headless --CreateProfile default >/dev/null 2>&1
        profile=$(grep -oP '^Path=\K.*' "$profiles_ini" | head -n1)
        dir="$HOME/.mozilla/firefox/$profile"
        certutil -N -d "sql:$dir" --empty-password
        password_file=$(mktemp -p "''${XDG_RUNTIME_DIR:-/tmp}" cert-password.XXXXXX)
        trap 'rm -f "$password_file"' EXIT
        if [ -r /run/qemu-vm-files/cert.password ]; then
          cp /run/qemu-vm-files/cert.password "$password_file"
        else
          zenity --password --title "AutoFirma VM" > "$password_file"
        fi
        import-certificate "$cert" "$password_file" \
          || zenity --error --title "AutoFirma VM" --text "The certificate import failed."
      fi
      exec firefox
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
        <li>Stop the VM. Start it again with your certificate:
          <code>autofirma-vm --gui --file cert.p12=/path/to/cert.p12</code></li>
        <li>Type the certificate password in the dialog that opens.</li>
      </ol>
      <p>Or copy the file over SSH (the guest sshd has no SFTP, so
        <code>scp</code> does not work) and import it by hand:</p>
      <ol>
        <li><code>cat cert.p12 | ssh -p 2222 ${user}@localhost "cat - &gt; cert.p12"</code></li>
        <li>In a terminal here: <code>import-certificate cert.p12</code></li>
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

  programs = {
    autofirma = {
      enable = true;
      package = autofirma;
      # Creates the local CA in /etc/Autofirma and makes Firefox trust it.
      firefoxIntegration.enable = true;
    };

    firefox = {
      enable = true;
      autoConfig = ''
        pref("network.protocol-handler.expose.afirma", true);
        // Do not show the "Allow this site to open afirma links?" prompt.
        // AutoScript polls AutoFirma for a short time after the click. An
        // open prompt fails the signature. AutoFirma is the only external
        // handler in this guest.
        pref("security.external_protocol_requires_permission", false);
      '';
      policies = {
        # Send afirma:// to the desktop entry. Do not show the application
        # chooser.
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

    # -- Size -----------------------------------------------------------------
    # Removes the interactive tools of the shared home config.
    aldur.workstation.enable = false;
    firefox.wrapperConfig.speechSynthesisSupport = false;

    # -- User -----------------------------------------------------------------

    # Keep the editor out. This guest is a browser appliance.
    aldur.lazyvim.enable = lib.mkDefault false;
  };

  # The oneshot of the module writes the WebSocket keystore as root with
  # mode 0600. AutoFirma runs as the user and cannot read it. Each socket
  # attempt then fails with SAF_45. The keystore password is fixed
  # upstream ("654321"), so mode 0644 loses nothing. The upstream tests
  # run as root and do not see this.
  systemd.services.create-autofirma-cert.serviceConfig.ExecStartPost =
    "${pkgs.coreutils}/bin/chmod 0644 /etc/Autofirma/autofirma.pfx";

  environment = {
    etc."autofirma-vm/index.html".source = startPage;

    # Start Firefox with the session.
    etc."xdg/autostart/autofirma-vm-firefox.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Firefox
      Exec=${lib.getExe firefox-session}
      OnlyShowIn=XFCE;
    '';

    systemPackages = [
      import-certificate
      pkgs.nss.tools
      # For clipboard checks by hand; see the README.
      pkgs.xclip
    ];

    # Firefox 154 creates new profiles under ~/.config/mozilla. On Linux,
    # AutoFirma only reads ~/.mozilla/firefox/profiles.ini. Keep the legacy
    # location, or AutoFirma finds no certificates.
    sessionVariables.MOZ_LEGACY_HOME = "1";

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

  # All glibc locales take 220 MiB. Two locales are sufficient.
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "es_ES.UTF-8/UTF-8"
  ];

  # The X server enables the default font set. That set includes the CJK
  # Noto fonts (120 MiB). fonts.packages below covers Latin scripts.
  fonts.enableDefaultPackages = false;

  services = {
    # Speech synthesis pulls speech-dispatcher and 650 MiB of mbrola voices.
    # Each graphical desktop enables it, and the Firefox wrapper too.
    speechd.enable = lib.mkForce false;

    # Virtual filesystems and thumbnails pull samba, GNOME online accounts,
    # and webkitgtk. Thunar works without them.
    gvfs.enable = lib.mkForce false;
    tumbler.enable = lib.mkForce false;

    # Clipboard sharing with the host. The agent needs the virtio serial
    # port that `qemu-vm --clipboard` adds. Without it, it exits.
    spice-vdagentd.enable = true;

    # -- Desktop --------------------------------------------------------------
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

  documentation.nixos.enable = false;

  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
  ];
}
