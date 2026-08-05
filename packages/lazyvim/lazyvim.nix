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
    hosts.python3.enable = false;
    hosts.node.enable = false;
    # aliases = [ defaultPackageName ];
  };

  allCategories = {
    general = true;

    ide = true;
    treesitterAll = true;

    beancount = false;
    go = true;
    json = true;
    markdown = true;
    nix = true;
    python = true;
    rust = true;
    solidity = true;
    toml = true;
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
        # From the overlay (packages/neovim-nightly): master built from
        # source, no neovim-nightly-overlay input.
        neovim-unwrapped = pkgs.neovim-nightly;
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
  "${defaultPackageName}-nightly" = nixCatsBuilder "${defaultPackageName}-nightly";

  defaultModule = utils.mkNixosModules moduleArgs;
  defaultHomeModule = utils.mkHomeModules moduleArgs;
}
