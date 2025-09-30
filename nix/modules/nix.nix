{ pkgs, inputs, ... }: {
  nix = {
    settings = { experimental-features = "nix-command flakes"; };

    package = pkgs.nixVersions.latest;

    optimise = { automatic = true; };

    # Pin nixpkgs to the flake input, so that the packages installed
    # come from the flake inputs.nixpkgs.url.
    registry.nixpkgs.flake = inputs.nixpkgs;
  };
}
