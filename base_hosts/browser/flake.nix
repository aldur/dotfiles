{
  description = "A persistent Firefox VM for ChromeOS Baguette and QEMU.";

  inputs = {
    aldur-dotfiles.url = "github:aldur/dotfiles";
    nixos-crostini = {
      url = "github:aldur/nixos-crostini/626c356166f64fe3d2fe1b94601c5a86379be18b";
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
