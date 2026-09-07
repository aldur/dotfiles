final: prev: {
  nix-direnv = import ../../utils/override-until-upgrade.nix {
    package = prev.nix-direnv;
    # nix-direnv 3.1.2 (the latest release) logs via >/dev/stderr,
    # which reopens /proc/self/fd/2 and fails (EACCES/ENXIO) when
    # stderr can't be reopened by path — e.g. inside Apple containers,
    # or when driven from Node via socketpair stdio. Fixed on master
    # by https://github.com/nix-community/nix-direnv/pull/753 but not
    # yet in any release, so build the nixpkgs package from a pinned
    # master commit.
    version = "3.1.2";
    note = "Drop the master pin in overlays/overrides/nix-direnv.nix if the new version contains nix-direnv PR #753.";
    replacement = prev.nix-direnv.override {
      # resholve.mkDerivation builds from a copy of the tree, so patch
      # the source instead of the package.
      fetchFromGitHub =
        args:
        prev.applyPatches {
          src = prev.fetchFromGitHub (
            args
            // {
              # master @ 2026-07-05
              rev = "d9d9a251973ce45c28323b27dc9fb50165c82618";
              hash = "sha256-lZVr32AB5aP+rvzdcrbnkyuSxx1mcgLaUi8/eClsvlE=";
            }
          );
          patches = [
            # Log the "files newer than cache" list through log_status.
            ./nix-direnv-log-status-file-list.patch
          ];
        };
    };
  };
}
