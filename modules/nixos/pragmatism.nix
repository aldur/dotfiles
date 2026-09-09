{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.pragmatism;
in
{
  # https://fzakaria.com/2025/02/26/nix-pragmatism-nix-ld-and-envfs
  #
  # Trade some of hardening.nix's attack-surface reduction for foreign-binary
  # compatibility: nix-ld runs arbitrary dynamically-linked
  # binaries and envfs (FUSE) auto-populates /usr/bin.
  options.pragmatism = {
    nixLd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run foreign dynamically-linked binaries with nix-ld.";
    };

    envfs.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Mount envfs over /usr/bin and /bin. A hardcoded shebang such as
        `#!/usr/bin/python3` then runs the tool on the PATH of the caller.
        The mount is a root FUSE daemon. Without it, NixOS provides only
        /bin/sh and /usr/bin/env.
      '';
    };
  };

  config = {
    programs.nix-ld = lib.mkIf cfg.nixLd.enable {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
      ];
    };

    services.envfs.enable = cfg.envfs.enable;
  };
}
