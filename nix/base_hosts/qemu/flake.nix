{
  description = "A QEMU NixOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../../..?dir=nix";
      url = "github:aldur/dotfiles?dir=nix";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };
  outputs = { nixos-generators, aldur-dotfiles, ... }:
    let
      modules = [ aldur-dotfiles.nixosModules.default ./qemu.nix ];
      targetSystem = "aarch64-linux";
      specialArgs = aldur-dotfiles.specialArgs;
    in aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import aldur-dotfiles.inputs.nixpkgs { inherit system; };
      in {
        packages = rec {
          vm-nogui = nixos-generators.nixosGenerate {
            inherit specialArgs;
            system = targetSystem;
            modules = modules ++ [
              # Let's setup the VM
              ({ ... }: {
                virtualisation.diskSize = 64 * 1024;
                virtualisation.cores = 8;

                # By default `nix` builds under /tmp, which is constrained by RAM size:
                # https://discourse.nixos.org/t/
                # no-space-left-on-device-error-when-rebuilding-but-plenty-of-storage-available/43862/9
                virtualisation.memorySize = 16 * 1024;

                # Instead, write to the machine's filesystem.
                virtualisation.writableStoreUseTmpfs = false;

                # This allows building from macOS
                # pkgs refers to the host's packages
                virtualisation.qemu.package = pkgs.qemu;
                virtualisation.host.pkgs = pkgs;
              })
            ];
            format = "vm-nogui";
          };
          default = vm-nogui;
        };
      }) // {
        nixosConfigurations.qemu-nixos =
          aldur-dotfiles.inputs.nixpkgs.lib.nixosSystem {
            inherit specialArgs modules;
            system = targetSystem;
          };
      };
}
