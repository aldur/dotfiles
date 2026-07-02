{ pkgs, ... }:
let
  dashDocsetsDir = ".local/share/dasht/docsets";

  download-nix-docsets = pkgs.writeShellApplication {
    name = "download-nix-docsets";
    runtimeInputs = with pkgs; [
      curl
      gnutar
      coreutils
    ];
    text = ''
      tmp="$(mktemp)"
      trap 'rm -f "$tmp"' EXIT

      # -f so curl fails (non-zero, no body) on an HTTP error instead of
      # piping an error page into tar; download to a temp file first so a
      # partial/failed transfer can't --overwrite the live docsets with
      # garbage. Extraction only runs once the download fully succeeds.
      curl -fsSL --proto '=https' -o "$tmp" \
        https://aldur.github.io/nixpkgs.docset/all.tgz

      mkdir -p "$DASHT_DOCSETS_DIR"
      tar --overwrite -xzf "$tmp" -C "$DASHT_DOCSETS_DIR"
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
