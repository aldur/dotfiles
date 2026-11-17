{
  description = "A NixOS guest for the Android Terminal app (AVF) from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };

    nixos-avf = {
      url = "github:nix-community/nixos-avf";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
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
        # The disk image step runs in a VM and asks for the `kvm` feature,
        # but the arm64 GitHub runners have no KVM. Without the request,
        # qemu emulates the VM. That step only installs the boot loader.
        avf-image = avf-nixos.config.system.build.avfImage.override (old: {
          raw_disk_image = nixpkgs.lib.overrideDerivation old.raw_disk_image (_: {
            requiredSystemFeatures = [ ];
          });
        });
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
