{ lib, ... }: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Temporarily disable to allow this to co-exist with deteminate nix.
  nix.enable = false;
  nix.optimise.automatic = lib.mkForce false;
  home-manager.backupFileExtension = "home-manager-backup";

  programs.aldur.lazyvim.enable = true;
  programs.aldur.lazyvim.packageNames = [ "lazyvim" ];
}
