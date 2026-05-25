{ pkgs, ... }: {
  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib zlib ];
    };
  };

  services = { envfs = { enable = true; }; };
}
