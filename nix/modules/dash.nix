{ pkgs, lib, ... }:
with lib;
let
  basePackages = with pkgs; [
    dasht
    dashp
    w3m
  ];

  dashDocsetsDir = ".local/share/dasht/docsets";

  download-nix-docsets = pkgs.writeShellApplication {
    name = "download-nix-docsets";
    runtimeInputs = with pkgs; [
      curl
      gnutar
    ];
    text = ''
      curl https://aldur.github.io/nixpkgs.docset/all.tgz | tar --overwrite -xzf - -C "$DASHT_DOCSETS_DIR"
    '';
  };
in
{
  environment.systemPackages = basePackages;

  home-manager.users.aldur = _: {
    home = {
      file."${dashDocsetsDir}/.keep".text = "";
      sessionVariables = {
        DASHT_DOCSETS_DIR = "$HOME/${dashDocsetsDir}";
      };
      packages = [ download-nix-docsets ];
    };
  };
}
