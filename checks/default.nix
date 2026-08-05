{
  pkgs,
  # This flake and its inputs, for the pins it discovers and the system the
  # headless check evaluates.
  self,
  inputs,
  # The package sets the repo-wide checks walk. Bound by flake.nix rather than
  # read back off `self`, which would make the checks depend on their own flake.
  packages,
  overlayPackages,
}:

# The flake's `checks` output.
#
# Checks about the repo as a whole live in this directory. Tests of one
# specific thing stay next to what they test — a package's `passthru.tests`, a
# module's `tests/` — and are only wired up from here, so they are also
# reachable the way that thing is used (`nix-update --test`, for one).

let
  inherit (pkgs.stdenv.hostPlatform) system;
in

{
  # Fails if a package pins a source without saying how to bump it.
  pinned-packages = pkgs.callPackage ./pinned-packages.nix {
    discovered = self.legacyPackages.${system}.discoveredPins;
  };

  # Fails if nixpkgs has caught up with a package this repo only carries
  # because nixpkgs lacked it.
  nixpkgs-absence = pkgs.callPackage ./nixpkgs-absence.nix {
    candidates = packages // overlayPackages;
    # `legacyPackages` rather than a fresh `import`: the same memoized,
    # un-overlaid package set the rest of this flake reuses.
    upstream = inputs.nixpkgs.legacyPackages.${system};
  };

  # Carried as `passthru.tests` on the packages, so `nix-update --test` runs
  # them on a bump too.
  gpg-encrypt = pkgs.gpg-encrypt.tests.integration;
  taskmd = pkgs.taskmd.tests.version;

  # The editor's light/full split stays split: both start headless, the heavy
  # language tooling stays in full and out of light.
  lazyvim-variants = pkgs.callPackage ./lazyvim-variants.nix {
    inherit (packages) lazyvim lazyvim-light;
  };
}
// pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  # Tests a darwin module's config merging, which is pure evaluation and so
  # runs on the cheaper Linux runners.
  merge-container-config =
    pkgs.callPackage ../modules/darwin/tests/merge-container-config-test.nix
      { };

  headless-defaults = pkgs.callPackage ./headless-defaults.nix {
    inherit self inputs system;
  };
}
