{
  description = "A NixOS guest for the Android Terminal app (AVF) from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };
  };
  outputs =
    { aldur-dotfiles, ... }@inputs:
    let
      inherit (aldur-dotfiles.inputs) nixpkgs;
      system = "aarch64-linux";

      avf-nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
        modules = [
          aldur-dotfiles.nixosModules.default
          ./avf.nix
        ];
      };
    in
    {
      packages.${system} = rec {
        avf-image = avf-nixos.config.system.build.avfImage;
        default = avf-image;
      };

      # The SBOM of the system in avf-image. CI attests it to the image.
      apps.${system}.sbom-avf = aldur-dotfiles.lib.mkSbomApp {
        pkgs = nixpkgs.legacyPackages.${system};
        configuration = avf-nixos;
      };

      # Having this allows rebuilding the system _within_ the guest.
      nixosConfigurations = { inherit avf-nixos; };
    };
}
