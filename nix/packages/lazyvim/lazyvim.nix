{ inputs, pkgs }:
let
  inherit (inputs.nixCats) utils;
  luaPath = ./.;

  dependencyOverlays = import ./overlays inputs;

  categoryDefinitions =
    { pkgs, ... }:
    {
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
    beancount = true;
    nix = true;
  };

  packageDefinitions = {
    ${defaultPackageName} = _: {
      inherit settings;
      categories = allCategories;
      extra = { };
    };
    "${defaultPackageName}-nightly" = _: {
      settings = settings // {
        neovim-unwrapped =
          inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      categories = allCategories;
      extra = { };
    };
    "${defaultPackageName}-light" = _: {
      inherit settings;
      categories = {
        general = true;
      };
      extra = { };
    };
  };

  nixCatsBuilder = utils.baseBuilder luaPath {
    inherit pkgs dependencyOverlays;
  } categoryDefinitions packageDefinitions;

  defaultPackage = nixCatsBuilder defaultPackageName;
  moduleArgs = {
    inherit
      luaPath
      defaultPackageName
      categoryDefinitions
      packageDefinitions
      dependencyOverlays
      ;
  }
  // {
    moduleNamespace = [
      "programs"
      "aldur"
      "lazyvim"
    ];
  };
in
{
  "${defaultPackageName}" = defaultPackage;
  "${defaultPackageName}-light" = nixCatsBuilder "${defaultPackageName}-light";

  defaultModule = utils.mkNixosModules moduleArgs;
  defaultHomeModule = utils.mkHomeModules moduleArgs;
}
