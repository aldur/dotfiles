{ inputs, pkgs, }:
let
  inherit (inputs.nixCats) utils;
  luaPath = ./.;

  dependencyOverlays = (import ./overlays inputs);

  categoryDefinitions = { pkgs, ... }: {
    lspsAndRuntimeDeps = pkgs.callPackage ./runtime.nix { };
    startupPlugins = pkgs.callPackage ./plugins.nix { };
    environmentVariables = pkgs.callPackage ./environment.nix { };
  };

  defaultPackageName = "lazyvim";

  settings = {
    suffix-path = true;
    suffix-LD = true;
    wrapRc = true;
    configDirName = defaultPackageName;
    # hosts.python3.enable = false;
    # hosts.node.enable = false;
    # aliases = [ defaultPackageName ];
  };

  allCategories = {
    general = true;
    rust = true;
    go = true;
    typescript = true;
    solidity = true;
  };

  packageDefinitions = {
    ${defaultPackageName} = { ... }: {
      inherit settings;
      categories = allCategories;
      extra = { };
    };
    "${defaultPackageName}-nightly" = { ... }: {
      settings = settings // {
        neovim-unwrapped =
          inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
      };
      categories = allCategories;
      extra = { };
    };
    "${defaultPackageName}-light" = { ... }: {
      inherit settings;
      categories = { general = true; };
      extra = { };
    };
  };

  nixCatsBuilder =
    utils.baseBuilder luaPath { inherit pkgs dependencyOverlays; }
    categoryDefinitions packageDefinitions;

  defaultPackage = nixCatsBuilder defaultPackageName;
  moduleArgs = {
    inherit luaPath defaultPackageName categoryDefinitions packageDefinitions
      dependencyOverlays;
  };
in {
  "${defaultPackageName}" = defaultPackage;

  defaultModule = utils.mkNixosModules moduleArgs // {
    moduleNamespace = [ "programs" "aldur" "lazyvim" ];
  };
  defaultHomeModule = utils.mkHomeModules moduleArgs;
}
