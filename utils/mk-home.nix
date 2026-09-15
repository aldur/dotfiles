# A standalone Home Manager configuration, using the same packages as our hosts.
{ inputs }:
{
  system,
  username ? null,
  homeDirectory ? null,
  stateVersion ? "26.05",
  modules ? [ ],
}:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  extraSpecialArgs = { inherit inputs; };
  modules = [
    ../modules/home/home.nix
    ../base_hosts/home-manager/linux.nix
    ({ config, lib, ... }: {
      home = {
        username = lib.mkDefault (if username == null then config.mainUser else username);
        homeDirectory = lib.mkDefault (
          if homeDirectory == null then "/home/${config.home.username}" else homeDirectory
        );
        stateVersion = lib.mkDefault stateVersion;
      };
    })
  ]
  ++ modules;
}
