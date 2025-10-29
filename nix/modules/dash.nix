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

  home-manager.users.aldur =
    { ... }:
    {
      home.file."${dashDocsetsDir}/.keep".text = "";
      home.sessionVariables = {
        DASHT_DOCSETS_DIR = "$HOME/${dashDocsetsDir}";
      };
      home.packages = [ download-nix-docsets ];
    };
}
