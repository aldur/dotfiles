{
  description = "A persistent Firefox VM for ChromeOS Baguette and QEMU.";

  inputs = {
    aldur-dotfiles.url = "github:aldur/dotfiles";
    nixos-crostini = {
      url = "github:aldur/nixos-crostini/main";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.aldur-dotfiles.lib.mkGuiAppliance {
      inherit inputs;
      name = "browser";
      directory = ./.;
    };
}
