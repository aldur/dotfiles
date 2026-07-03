{ pkgs, ... }: {
  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  #
  # Deliberately trades some of hardening.nix's attack-surface reduction for
  # foreign-binary compatibility: nix-ld runs arbitrary dynamically-linked
  # binaries and envfs (FUSE) auto-populates /usr/bin. Opt-in per host; don't
  # cargo-cult onto a locked-down box.
  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc.lib zlib ];
    };
  };

  services = { envfs = { enable = true; }; };
}
