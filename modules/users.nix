{
  pkgs,
  config,
  lib,
  ...
}:
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

  config.users.users.${config.mainUser} = {
    shell = pkgs.fish;
  };
}
