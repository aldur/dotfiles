{
  inputs,
  name,
  directory,
}:
let
  inherit (inputs) aldur-dotfiles;
  inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;
  guestInputs = inputs // { appliance = inputs.self; };
  specialArgs = aldur-dotfiles.lib.mkSpecialArgs guestInputs;
  qemu = aldur-dotfiles.lib.mkQemuGuest {
    inputs = guestInputs;
    name = "${name}-vm";
    hostName = "${name}-vm";
    qemuModule = (directory + /desktop.nix);
    vmOverrides = {
      baseModules = [ ];
      compressStoreImage = true;
      defaultVmDir = "$HOME/.local/share/${name}-vm";
      defaultMemory = 4096;
      defaultCores = 4;
      defaultDiskSize = 12;
      defaultEphemeral = false;
      defaultClipboard = false;
    };
  };
  guest =
    system:
    nixpkgs.lib.nixosSystem {
      inherit system;
      inherit specialArgs;
      modules = [ (directory + /baguette.nix) ];
    };
in
nixpkgs.lib.recursiveUpdate qemu (
  flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
    system:
    let
      configuration = guest system;
    in
    {
      packages = {
        baguette-zimage = configuration.config.system.build.btrfsImageCompressed;
        system = configuration.config.system.build.toplevel;
      };
      apps.sbom-baguette = aldur-dotfiles.lib.mkSbomApp {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit configuration;
      };
      checks = import ../base_hosts/appliance/tests {
        inherit configuration directory inputs name specialArgs;
        pkgs = nixpkgs.legacyPackages.${system};
      };
    }
  )
  // {
    nixosConfigurations.${name} = guest "aarch64-linux";
  }
)
