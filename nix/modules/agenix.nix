{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.age}/bin/age";
in
{
  age.ageBin = ageBin;
  home-manager.users.aldur =
    { ... }:
    {
      imports = [ inputs.agenix.homeManagerModules.default ];
      systemd.user.services.agenix.Service.Environment = "PATH=$PATH:${
        lib.makeBinPath [ pkgs.age-plugin-yubikey ]
      }";
    };
}
