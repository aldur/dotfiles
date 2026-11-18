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

      mkAvf =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
          modules = [
            aldur-dotfiles.nixosModules.default
            ./avf.nix
          ];
        };
      avf-nixos = mkAvf system;
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

      # The app is also for x86_64, and only the x86_64 runners have KVM.
      checks.x86_64-linux.avf-boot = nixpkgs.legacyPackages.x86_64-linux.callPackage ./tests/boot.nix {
        configuration = mkAvf "x86_64-linux";
      };

      # Having this allows rebuilding the system _within_ the guest.
      nixosConfigurations = { inherit avf-nixos; };
    };
}
