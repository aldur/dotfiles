{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.age}/bin/age";
in
{
  age.ageBin = ageBin;
  home-manager.users.${config.mainUser} =
    { ... }:
    {
      imports = [ inputs.agenix.homeManagerModules.default ];
      systemd.user.services.agenix.Service.Environment = "PATH=$PATH:${
        lib.makeBinPath [ pkgs.age-plugin-yubikey ]
      }";
    };
}
