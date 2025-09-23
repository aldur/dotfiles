{
  lib,
  ...
}:
with lib;
{
  options.nixpkgs = {
    allowUnfreeByName = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Allowed unfree to install";
    };
  };

  config.nixpkgs.overlays = [
    (import ../overlays/yubikey-agent.nix)
    (import ../overlays/beancount-language-server.nix)
  ];
}
