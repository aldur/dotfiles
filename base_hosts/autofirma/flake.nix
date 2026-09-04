{
  description = "A QEMU NixOS guest that runs AutoFirma, from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };

    autofirma-nix = {
      url = "github:nix-community/autofirma-nix";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
      inputs.home-manager.follows = "aldur-dotfiles/home-manager";
    };

    nixos-crostini = {
      url = "github:aldur/nixos-crostini";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };

  outputs =
    { aldur-dotfiles, ... }@inputs:
    let
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;
      inherit (nixpkgs) lib;

      specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      guest = aldur-dotfiles.lib.mkQemuGuest {
        inherit inputs;
        name = "autofirma-vm";
        hostName = "autofirma-vm";
        qemuModule = ./autofirma.nix;

        vmOverrides = {
          defaultVmDir = "$HOME/.local/share/autofirma-vm";
          defaultMemory = 4096;
          defaultCores = 4;
          defaultDiskSize = 16;
          # Nothing survives a session: no profile, no cookies, no CA. The
          # certificate comes in with `--file` each time.
          defaultEphemeral = true;
          defaultClipboard = true;
        };
      };

      # The same guest as a ChromeOS Baguette image. See baguette.nix.
      mkBaguette =
        system:
        lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./baguette.nix ];
        };
      baguette = {
        nixosConfigurations = {
          # The hostname names the configuration: `nixos-rebuild` inside the
          # VM selects it that way.
          autofirma-baguette = mkBaguette "aarch64-linux";
          autofirma-baguette-x86_64 = mkBaguette "x86_64-linux";
        };
      }
      // flake-utils.lib.eachSystem linuxSystems (system: {
        packages.baguette-zimage = (mkBaguette system).config.system.build.btrfsImageCompressed;
      });

      checks = flake-utils.lib.eachSystem linuxSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          testCert = import ./tests/test-cert.nix { inherit pkgs; };
        in
        {
          checks = {
            # Boots the QEMU guest, imports a test certificate into Firefox,
            # and signs a document through the afirma:// WebSocket flow.
            sign-via-websocket = pkgs.callPackage ./tests/sign-via-websocket.nix {
              guestModule = ./desktop.nix;
              baseModule = aldur-dotfiles.nixosModules.default;
              inherit specialArgs;
              inherit (inputs) autofirma-nix;
            };

            # Boots the Baguette image in crosvm and probes it. The generic
            # part of the probe is in utils/baguette-test.nix of the
            # dotfiles. The steps below are the ones of this guest.
            baguette-boot = aldur-dotfiles.lib.mkBaguetteTest {
              configuration = mkBaguette system;
              name = "autofirma-baguette-boot";
              # AutoFirma only reads ~/.mozilla/firefox/profiles.ini, and
              # Firefox 154 creates new profiles under ~/.config/mozilla.
              userEnv.MOZ_LEGACY_HOME = "1";
              probeFiles = {
                "ciudadano.p12" = "${testCert}/ciudadano.p12";
                "password" = "${testCert}/password";
              };
              extraProbe = ''
                echo "PROBE pfx $(stat -c %a /etc/Autofirma/autofirma.pfx)"
                echo "PROBE ca $(stat -c %s /etc/Autofirma/Autofirma_ROOT.cer)"
                echo "PROBE launcher $(ls /run/current-system/sw/share/applications/ | tr '\n' ' ')"

                # Firefox starts with the policies of the guest and renders
                # the start page.
                as_user timeout 180 firefox --headless \
                  --screenshot /home/$user/start.png \
                  file:///etc/autofirma-vm/index.html > /tmp/firefox.log 2>&1
                echo "PROBE firefox $(stat -c %s /home/$user/start.png 2>/dev/null || echo none)"

                # The certificate import of the session wrapper. Firefox
                # made the database above. On an existing database,
                # `certutil -N` asks for the old password on /dev/tty and
                # waits forever.
                profile=$(grep -oP '^Path=\K.*' /home/$user/.mozilla/firefox/profiles.ini | head -n1)
                dir=/home/$user/.mozilla/firefox/$profile
                [ -f "$dir/cert9.db" ] || as_user certutil -N -d "sql:$dir" --empty-password > /dev/null 2>&1
                as_user import-certificate $probe/ciudadano.p12 $probe/password > /tmp/import.log 2>&1
                echo "PROBE import $(as_user certutil -L -d "sql:$dir" 2>/dev/null | grep -c -i ficticio)"

                # AutoFirma starts in its FHS sandbox on the trimmed JRE.
                # Without a display, AWT stops it. The class names show
                # that the JRE ran the jar.
                as_user timeout 60 autofirma > /tmp/autofirma.log 2>&1
                echo "PROBE autofirma exit $? $(grep -c 'es.gob.afirma\|java.awt' /tmp/autofirma.log)"
                head -n 5 /tmp/autofirma.log
              '';
              extraChecks = [
                # The keystore of the WebSocket must be readable by the user.
                "pfx 644"
                "ca [1-9]"
                "launcher .*autofirma-vm-firefox.desktop"
                "firefox [1-9]"
                "import [1-9]"
                "autofirma exit [0-9]* [1-9]"
              ];
            };
          };
        }
      );

    in
    lib.foldl lib.recursiveUpdate { } [
      guest
      baguette
      checks
    ];
}
