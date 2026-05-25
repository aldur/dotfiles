{ ... }: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config = import ../shared/programs/direnv.nix;
  };
}
