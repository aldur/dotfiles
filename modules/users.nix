{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.identity;
in
{
  options.mainUser = lib.mkOption {
    type = lib.types.str;
    default = "aldur";
    description = ''
      The primary interactive user. Threaded through the user account,
      home-manager, and per-user hardening/service settings so the config
      isn't pinned to one username.
    '';
  };

  options.identity = {
    githubUser = lib.mkOption {
      type = lib.types.str;
      default = "aldur";
      description = ''
        The GitHub account of the primary user. It gives the git identity
        and the default of `identity.authorizedKeys`.
      '';
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.githubUser}@users.noreply.github.com";
      description = ''
        The git `user.email` of the primary user. Also the principal of the
        signing keys in the git allowed-signers file.
      '';
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = import ../utils/github-keys.nix { username = cfg.githubUser; };
      defaultText = lib.literalExpression "the keys of `https://github.com/<identity.githubUser>.keys`";
      description = ''
        The SSH public keys that can log in as the primary user, and as
        root on the guests. For an account other than `aldur`, pass the
        hash too: `utils.github-keys { username = …; sha256 = …; }`.
      '';
    };
  };

  config.users.users.${config.mainUser} = {
    shell = pkgs.fish;
  };
}
