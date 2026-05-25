{ pkgs, ... }:
let
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
  home = {
    packages = with pkgs; [
      dasht
      dashp
      w3m
      download-nix-docsets
    ];

    file."${dashDocsetsDir}/.keep".text = "";

    sessionVariables = {
      DASHT_DOCSETS_DIR = "$HOME/${dashDocsetsDir}";
    };
  };
}
