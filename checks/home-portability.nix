# Force the activation derivations: checking a few option values alone misses
# undefined module arguments and package failures in disabled/default branches.
{
  self,
  inputs,
  pkgs,
}:
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  standalone = self.legacyPackages.${system}.homeConfiguration;
  custom = self.lib.mkHome {
    inherit system;
    username = "alice";
    homeDirectory = "/srv/alice";
    modules = [
      {
        identity.githubUser = "alice";
        identity.authorizedKeys = [ "standalone-key" ];
        programs.aldur = {
          workstation.enable = false;
          lazyvim.enable = false;
          claude-code.enable = true;
          codex.enable = true;
        };
        programs.better-nix-search.enable = true;
      }
    ];
  };
  nixos = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      self.nixosModules.default
      {
        mainUser = "alice";
        extraUsers = [ "bob" ];
        users.users.bob = {
          isNormalUser = true;
          home = "/home/bob";
        };
        identity = {
          githubUser = "alice";
          email = "alice@example.org";
          authorizedKeys = [
            "first-system-key"
            "second-system-key"
          ];
        };
        programs.aldur = {
          workstation.enable = false;
          codex.enable = true;
          lazyvim.enable = true;
        };
        home-manager.users.bob = {
          programs.aldur.codex.enable = false;
          programs.aldur.claude-code.enable = true;
          identity.authorizedKeys = [ "bob-only-key" ];
        };
      }
    ];
  };
  alice = nixos.config.home-manager.users.alice;
  bob = nixos.config.home-manager.users.bob;

  # Evaluate the actual Darwin home module and bridge with a small system
  # fixture. This uses the Darwin overlays but needs neither a Mac builder nor
  # the host-only Homebrew/Rosetta inputs of the macOS template.
  darwinOverlays =
    (import ../modules/darwin/nixpkgs.nix {
      inherit inputs;
      pkgs = darwinPkgs;
      pkgsUnstable = darwinUnstable;
      config.nixpkgs.config = { };
    }).nixpkgs.overlays;
  darwinPkgs = import inputs.nixpkgs-darwin {
    system = "aarch64-darwin";
    overlays =
      (import ../modules/nixpkgs.nix {
        inherit inputs lib;
        pkgs = darwinPkgs;
        config.nixpkgs.allowUnfreeByName = [ ];
      }).config.nixpkgs.overlays
      ++ darwinOverlays;
  };
  darwinUnstable = import inputs.nixpkgs-unstable {
    system = "aarch64-darwin";
    inherit (darwinPkgs) overlays;
  };
  darwinSystem = nixos.config // {
    programs = nixos.config.programs // {
      aldur = nixos.config.programs.aldur // {
        lazyvim.enable = false;
        editorPackage = null;
        codex = nixos.config.programs.aldur.codex // {
          enable = false;
        };
        claude-code = nixos.config.programs.aldur.claude-code // {
          preferLocalInstallation = true;
        };
      };
    };
  };
  darwin = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = darwinPkgs;
    extraSpecialArgs = {
      inherit inputs;
      stateVersion = "25.05";
      pkgsUnstable = darwinUnstable;
      osConfig = darwinSystem;
    };
    modules = [ ../modules/darwin/home.nix ];
  };
  declarations =
    (import ../modules/shared/options.nix {
      config = nixos.config;
      inherit pkgs lib;
    }).options;
  sharedPaths = lib.collect builtins.isList (
    lib.mapAttrsRecursiveCond (value: !lib.isOption value) (path: _: path) declarations
  );
  comparable = value: if lib.isDerivation value then value.drvPath else value;
  drift =
    source: home:
    lib.filter (
      path: comparable (lib.getAttrFromPath path source) != comparable (lib.getAttrFromPath path home)
    ) sharedPaths;
  nixosDrift = drift nixos.config alice;
  darwinDrift = drift darwinSystem darwin.config;
  hasPackage = name: home: lib.any (p: lib.getName p == name) home.home.packages;
  require = message: condition: lib.assertMsg condition "home portability: ${message}";
in
assert require (
  "shared options drifted: "
  + lib.concatMapStringsSep ", " (lib.concatStringsSep ".") (nixosDrift ++ darwinDrift)
) (nixosDrift == [ ] && darwinDrift == [ ]);
assert require "home-only tools and aliases" (
  hasPackage "totp-cli" alice
  && hasPackage "totp-cli" standalone.config
  && !(lib.any (p: lib.getName p == "totp-cli") nixos.config.environment.systemPackages)
  &&
    lib.all
      (
        name:
        !(builtins.hasAttr name nixos.config.environment.shellAliases)
        && alice.home.shellAliases.${name} == standalone.config.home.shellAliases.${name}
        && darwin.config.home.shellAliases.${name} == standalone.config.home.shellAliases.${name}
      )
      [
        "gst"
        "gp"
        "gc"
        "ta"
        "tls"
      ]
);
assert require "developer tools stay in the user environment" (
  lib.all
    (
      package:
      lib.any (p: p.outPath == package.outPath) standalone.config.home.packages
      && !(lib.any (p: p.outPath == package.outPath) nixos.config.environment.systemPackages)
    )
    (
      with pkgs;
      [
        age
        universal-ctags
        watch
        ripgrep-all
        tree
        rig
        difftastic
      ]
    )
  && lib.all (name: hasPackage name alice) [
    "age"
    "tree"
    "rig"
  ]
);
assert require "authorized keys retain their order and per-user overrides remain possible" (
  alice.identity.authorizedKeys == [
    "first-system-key"
    "second-system-key"
  ]
  && custom.config.identity.authorizedKeys == [ "standalone-key" ]
  && bob.identity.authorizedKeys == [ "bob-only-key" ]
);
assert require "native app and build use the same configuration" (
  self.apps.${system}.home.program == "${standalone.activationPackage}/activate"
  && self.legacyPackages.${system}.home.drvPath == standalone.activationPackage.drvPath
  && self.apps.${system} ? validate-claude-settings
);
assert require "standalone defaults" (
  standalone.config.home.username == "aldur"
  && standalone.config.home.homeDirectory == "/home/aldur"
  && standalone.config.programs.git.settings.user.name == "aldur"
  && standalone.config.programs.git.settings.user.email == "aldur@users.noreply.github.com"
  && standalone.config.targets.genericLinux.enable
  && standalone.config.programs.aldur.lazyvim.enable
  && standalone.config.home.shellAliases.gst == "git status"
  && hasPackage "ripgrep" standalone.config
  && hasPackage "dashp" standalone.config
);
assert require "standalone customization and agent packages" (
  custom.config.home.username == "alice"
  && custom.config.home.homeDirectory == "/srv/alice"
  && custom.config.programs.git.settings.user.email == "alice@users.noreply.github.com"
  && custom.config.home.sessionVariables.EDITOR == "nvim"
  && !custom.config.programs.atuin.enable
  && hasPackage "codex" custom.config
  && custom.config.programs.claude-code.enable
);
assert require "Claude's unfree allowance stays local to its home module" (
  !(builtins.elem "claude-code" custom.config.nixpkgs.allowUnfreeByName)
  && !(builtins.elem "claude-code" nixos.config.nixpkgs.allowUnfreeByName)
  && !nixos.config.programs.aldur.claude-code.enable
  && bob.programs.claude-code.enable
  && bob.programs.claude-code.package.drvPath != ""
);
assert require "NixOS settings and per-user overrides" (
  alice.home.username == "alice"
  && bob.home.username == "bob"
  && alice.home.stateVersion == nixos.config.system.stateVersion
  && alice.programs.git.settings.user.email == "alice@example.org"
  && alice.programs.aldur.codex.enable
  && !bob.programs.aldur.codex.enable
  && !alice.programs.atuin.enable
  && alice.programs.aldur.editorPackage != null
);
assert require "Darwin settings" (
  darwin.config.home.homeDirectory == "/Users/alice"
  && darwin.config.home.stateVersion == "25.05"
  && darwin.config.programs.aldur.claude-code.preferLocalInstallation
  && !darwin.config.programs.tmux.secureSocket
);
pkgs.writeText "home-portability" (
  builtins.toJSON (
    map builtins.unsafeDiscardStringContext [
      standalone.activationPackage.drvPath
      custom.activationPackage.drvPath
      alice.home.activationPackage.drvPath
      bob.home.activationPackage.drvPath
      darwin.activationPackage.drvPath
    ]
  )
)
