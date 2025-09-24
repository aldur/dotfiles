{
  inputs,
  pkgs,
}:
let
  inherit (inputs.nixCats) utils;
  luaPath = ./.;

  categoryDefinitions =
    {
      pkgs,
      ...
    }:
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
  };

  packageDefinitions = {
    ${defaultPackageName} =
      {
        ...
      }:
      {
        inherit settings;
        categories = allCategories;
        extra = { };
      };
    "${defaultPackageName}-nightly" =
      {
        ...
      }:
      {
        settings = settings // {
          neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
        };
        categories = allCategories;
        extra = { };
      };
    "${defaultPackageName}-light" =
      {
        ...
      }:
      {
        inherit settings;
        categories = {
          general = true;
        };
        extra = { };
      };
  };

  nixCatsBuilder = utils.baseBuilder luaPath {
    inherit
      pkgs
      ;
  } categoryDefinitions packageDefinitions;
in
{
  inherit defaultPackageName;
  defaultPackage = nixCatsBuilder defaultPackageName;
  defaultModule = utils.mkNixosModules {
    moduleNamespace = [
      "programs"
      "aldur"
      "lazyvim"
    ];
    inherit
      luaPath
      defaultPackageName
      categoryDefinitions
      packageDefinitions
      ;
  };
  defaultHomeModule = utils.mkHomeModules {
    inherit
      luaPath
      defaultPackageName
      categoryDefinitions
      packageDefinitions
      ;
  };
}
