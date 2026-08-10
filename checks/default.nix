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
  taskmd-ui = pkgs.taskmd-ui.tests.smoke;

  # The editor's light/full split stays split: both start headless, the heavy
  # language tooling stays in full and out of light.
  lazyvim-variants = pkgs.callPackage ./lazyvim-variants.nix {
    inherit (packages) lazyvim lazyvim-light;
  };

  # Fails if the repo's own lua is not stylua-formatted.
  lua-format = pkgs.callPackage ./lua-format.nix { };

}
// pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
  # Budgets and forbidden-path guards for every derivation the flake
  # exports, discovered rather than enumerated so nothing is forgotten
  # (see overlays/slim.nix for why silent regressions are the risk).
  # Linux-only, like the repacks the budgets were measured against:
  # darwin hands back the stock packages, so there is no slimming to
  # guard — weighing those closures would only spend the macOS runner
  # building every package to judge it by someone else's numbers.
  slim-closures =
    let
      # Same trick as `overlayPackages` in flake.nix: the overlay's own
      # attr names, resolved through the final `pkgs`.
      slimPackages = builtins.intersectAttrs (import ../overlays/slim.nix pkgs pkgs) pkgs;
      candidates = slimPackages // overlayPackages // packages;
    in
    pkgs.callPackage ./slim-closures.nix {
      knownNames = builtins.attrNames candidates;
      packagesUnderGuard = pkgs.lib.filterAttrs (
        _: v:
        # tryEval: packages for other platforms throw when forced — some
        # only once instantiation reaches a platform-gated dependency
        # (c920-defaults wraps darwin's uvc-util), hence the drvPath probe.
        (builtins.tryEval (
          pkgs.lib.isDerivation v && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform v && v.drvPath != null
        )).value or false
      ) candidates;
    };

  # Forces every attribute the darwin overlays introduce, against the same
  # stable/unstable fixpoint a nix-darwin system would build. Pure evaluation,
  # so it runs on the cheaper Linux runners.
  darwin-overlays = pkgs.callPackage ./darwin-overlays.nix { inherit inputs; };

  # Tests a darwin module's config merging, which is pure evaluation and so
  # runs on the cheaper Linux runners.
  merge-container-config =
    pkgs.callPackage ../modules/darwin/tests/merge-container-config-test.nix
      { };

  headless-defaults = pkgs.callPackage ./headless-defaults.nix {
    inherit self inputs system;
  };
}
