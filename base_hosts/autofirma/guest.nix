{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  cfg = config.aldur.autofirma;

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

  # A runtime with the modules AutoFirma needs, not the full JDK (570 MiB).
  # jlink assembles it from the jmods of the JDK; nothing compiles. The
  # first eight come from `jdeps --print-module-deps autofirma.jar`. The
  # rest are service providers that jdeps cannot see: NSS through PKCS#11,
  # elliptic curves, locales, charsets, and accessibility.
  jre = pkgs.jre_minimal.override {
    modules = [
      "java.base"
      "java.desktop"
      "java.naming"
      "java.prefs"
      "java.security.jgss"
      "java.smartcardio"
      "java.sql"
      "java.xml.crypto"

      "java.logging"
      "java.management"
      "java.net.http"
      "java.scripting"
      "java.security.sasl"
      "jdk.accessibility"
      "jdk.charsets"
      "jdk.crypto.cryptoki"
      "jdk.crypto.ec"
      "jdk.localedata"
      "jdk.unsupported"
      "jdk.xml.dom"
      "jdk.zipfs"
    ];
  };

  autofirma = upstream.override (
    mavenHashes
    // {
      inherit jre;
      buildFHSEnv = buildFHSEnvSmallLocales;
    }
  );

  # certutil and pk12util alone. The `tools` output of nss also carries its
  # test binaries (45 MiB).
  nss-tools = pkgs.runCommand "nss-tools-small" { } ''
    mkdir -p $out/bin
    cp ${pkgs.nss.tools}/bin/{certutil,pk12util} $out/bin/
  '';

  # Imports a PKCS#12 certificate into each Firefox profile of the user.
  # AutoFirma reads the certificates from the Firefox (NSS) store. With no
  # password file, pk12util asks on the terminal.
  import-certificate = pkgs.writeShellApplication {
    name = "import-certificate";
    runtimeInputs = [
      nss-tools
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

  # Starts Firefox for the session. If `cert.p12` is in `filesDir` and the
  # profile has no user certificate yet, it imports the certificate first.
  # The password comes from `cert.password` if present, else from a
  # dialog. The password only touches a private file in /run/user.
  firefox-session = pkgs.writeShellApplication {
    name = "autofirma-vm-firefox";
    runtimeInputs = [
      config.programs.firefox.finalPackage
      import-certificate
      nss-tools
      # yad shares GTK 3 with Firefox. zenity brings GTK 4 and GStreamer.
      pkgs.yad
      pkgs.gnugrep
    ];
    text = ''
      cert=${cfg.filesDir}/cert.p12
      profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
      if [ -r "$cert" ]; then
        if [ ! -f "$profiles_ini" ]; then
          firefox --headless --CreateProfile default >/dev/null 2>&1
        fi
        profile=$(grep -oP '^Path=\K.*' "$profiles_ini" | head -n1)
        dir="$HOME/.mozilla/firefox/$profile"
        [ -f "$dir/cert9.db" ] || certutil -N -d "sql:$dir" --empty-password
        # A user certificate has the trust flags "u,u,u". Import once.
        if ! certutil -L -d "sql:$dir" | grep -q 'u,u,u'; then
          password_file=$(mktemp -p "''${XDG_RUNTIME_DIR:-/tmp}" cert-password.XXXXXX)
          trap 'rm -f "$password_file"' EXIT
          if [ -r ${cfg.filesDir}/cert.password ]; then
            cp ${cfg.filesDir}/cert.password "$password_file"
          else
            yad --entry --hide-text --title "AutoFirma VM" \
              --text "Certificate password:" > "$password_file"
          fi
          import-certificate "$cert" "$password_file" \
            || yad --image dialog-error --title "AutoFirma VM" \
              --text "The certificate import failed." --button OK:0
        fi
      fi
      exec firefox
    '';
  };

  # The launcher entry of the session wrapper. On ChromeOS, the launcher
  # shows it next to the plain Firefox entry.
  firefox-session-desktop = pkgs.makeDesktopItem {
    name = "autofirma-vm-firefox";
    desktopName = "Firefox (AutoFirma)";
    comment = "Firefox with the certificate from ${cfg.filesDir}";
    exec = "/run/current-system/sw/bin/autofirma-vm-firefox";
    icon = "firefox";
    categories = [
      "Network"
      "WebBrowser"
    ];
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
      <p>Firefox reads the certificate from <code>${cfg.filesDir}/cert.p12</code>
        when it starts. A file <code>cert.password</code> next to it skips the
        password dialog.</p>
      ${cfg.filesHelp}
      <p>Or import a file by hand. In a terminal here, run
        <code>import-certificate cert.p12</code>. Then restart Firefox.</p>
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

  options.aldur.autofirma = {
    filesDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Directory with `cert.p12` and, if present, `cert.password`. The
        session wrapper imports the certificate from there.
      '';
    };

    filesHelp = lib.mkOption {
      type = lib.types.lines;
      description = ''
        HTML for the start page. It tells how to put the certificate into
        `filesDir` on this platform.
      '';
    };
  };

  config = {
    programs = {
      autofirma = {
        enable = true;
        package = autofirma;
        # Creates the local CA in /etc/Autofirma and makes Firefox trust it.
        firefoxIntegration.enable = true;
      };

      firefox = {
        enable = true;
        # The wrapper reads these flags from the unwrapped package and
        # links the libraries: ffmpeg with its codecs, pipewire, Kerberos.
        # The sedes need none of them. The attribute update keeps the
        # unwrapped derivation as it is. The wrapper also links libcanberra
        # for GTK event sounds, and that pulls GStreamer with Python
        # (150 MiB). libcanberra without GStreamer is a small build.
        package =
          let
            libcanberra-gtk3 = pkgs.libcanberra-gtk3.override {
              gst_all_1 = pkgs.gst_all_1 // {
                gstreamer = null;
                gst-plugins-base = null;
              };
            };
          in
          (pkgs.wrapFirefox.override { inherit libcanberra-gtk3; })
            (
              pkgs.firefox-unwrapped
              // {
                ffmpegSupport = false;
                pipewireSupport = false;
                gssSupport = false;
              }
            )
            { };
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

      # -- Size ---------------------------------------------------------------
      firefox.wrapperConfig.speechSynthesisSupport = false;
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

      systemPackages = [
        import-certificate
        firefox-session
        firefox-session-desktop
        nss-tools
      ];

      # Firefox 154 creates new profiles under ~/.config/mozilla. On Linux,
      # AutoFirma only reads ~/.mozilla/firefox/profiles.ini. Keep the legacy
      # location, or AutoFirma finds no certificates.
      sessionVariables.MOZ_LEGACY_HOME = "1";
    };

    # All glibc locales take 220 MiB. Two locales are sufficient.
    i18n.supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "es_ES.UTF-8/UTF-8"
    ];

    # The default font set includes the CJK Noto fonts (120 MiB).
    # fonts.packages below covers Latin scripts.
    fonts.enableDefaultPackages = false;

    # Speech synthesis pulls speech-dispatcher and 650 MiB of mbrola voices.
    # Each graphical desktop enables it, and the Firefox wrapper too.
    services.speechd.enable = lib.mkForce false;

    documentation.nixos.enable = false;

    fonts.packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
    ];
  };
}
