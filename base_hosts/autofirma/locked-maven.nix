# Build the Maven repositories from versioned artifact URLs and SHA-256
# hashes. Repository metadata is part of the lock, never fetched live.
{
  lib,
  pkgs,
  upstreamInputs,
}:
let
  lock = builtins.fromJSON (builtins.readFile ./maven-lock.json);
  artifacts = lib.mapAttrs (
    path: hash:
    pkgs.fetchurl {
      url = "https://repo.maven.apache.org/maven2/${path}";
      inherit hash;
    }
  ) lock.artifacts;
  metadata = lib.mapAttrs (path: content: pkgs.writeText (baseNameOf path) content) lock.metadata;
  repositories = lib.mapAttrs (
    name: paths:
    pkgs.linkFarm name (
      map (path: {
        name = ".m2/repository/${path}";
        path = (artifacts // metadata).${path};
      }) paths
    )
  ) lock.repositories;
in
assert lib.assertMsg (
  lock.mavenVersion == pkgs.maven.version
) "AutoFirma: refresh maven-lock.json for Maven ${pkgs.maven.version}";
assert lib.assertMsg (lib.all (name: lock.sources.${name} == upstreamInputs.${name}.rev) (
  builtins.attrNames lock.sources
)) "AutoFirma: refresh maven-lock.json for the updated source revisions";
pkgs.stdenv
// {
  # autofirma-nix keeps its dependency fetchers private in each package.
  # Replace those three fixed-output derivations with the locked repos;
  # the upstream source preparation and offline compilation stay intact.
  mkDerivation =
    args:
    if builtins.isAttrs args && args ? outputHash then
      repositories.${args.name} or (throw "AutoFirma: no locked Maven repository for ${args.name}")
    else
      pkgs.stdenv.mkDerivation args;
}
