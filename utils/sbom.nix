# An app that writes the SBOM of a NixOS configuration. sbomnix walks the
# runtime closure of the system, so the SBOM lists what the image ships,
# not what built it. NIX_PATH points sbomnix at the pinned nixpkgs, and that
# fills the license and homepage of each package.
#
# `nix run …#sbom -- <dir>` writes sbom.spdx.json, sbom.cdx.json, and
# sbom.csv into <dir>. CI attests the SPDX file to the artifact it built
# from the same configuration.
{ nixpkgs }:
{
  pkgs,
  configuration,
  # Names the script. A container configuration has no hostname, so it
  # passes its image name.
  name ? configuration.config.system.name,
}:
let
  inherit (nixpkgs) lib;
  inherit (configuration.config.system.build) toplevel;
in
{
  type = "app";
  program = "${pkgs.writeShellScript "sbom-${name}" ''
    set -eu
    dir="''${1:-.}"
    mkdir -p "$dir"
    # sbomnix writes its HTTP cache to the working directory. Keep it with
    # the output.
    cd "$dir"
    export NIX_PATH="nixpkgs=${nixpkgs}"
    exec ${lib.getExe pkgs.sbomnix} ${toplevel} \
      --spdx ./sbom.spdx.json \
      --cdx ./sbom.cdx.json \
      --csv ./sbom.csv
  ''}";
}
