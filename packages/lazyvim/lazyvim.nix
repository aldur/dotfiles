{
  inputs,
  pkgs,
  pkgsUnstable,
}:
let
  inherit (inputs.nixCats) utils;
  luaPath = ./.;

  pinnedPlugins = pkgs.callPackage ./plugins { inherit pkgsUnstable; };

  categoryDefinitions =
    { pkgs, ... }:
    {
      lspsAndRuntimeDeps = pkgs.callPackage ./runtime.nix { };
      startupPlugins = pkgs.callPackage ./plugins.nix { inherit pkgsUnstable pinnedPlugins; };
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

    beancount = false;
    go = true;
    nix = true;
    rust = true;
    solidity = true;
    typescript = true;
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
    inherit pkgs;
  } categoryDefinitions packageDefinitions;

  # Rev-pinned plugins stay reachable (e.g. `lazyvim.plugins.tinymd-nvim`) so
  # nix-update can bump their pins in CI without dedicated flake outputs.
  withPinnedPlugins =
    drv:
    drv.overrideAttrs (prev: {
      passthru = (prev.passthru or { }) // {
        plugins = pinnedPlugins;
      };
    });

  defaultPackage = withPinnedPlugins (nixCatsBuilder defaultPackageName);
  moduleArgs = {
    inherit
      luaPath
      defaultPackageName
      categoryDefinitions
      packageDefinitions
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
