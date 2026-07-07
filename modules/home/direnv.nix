{ pkgs, ... }:
let
  overrideUntilUpgrade = import ../../utils/override-until-upgrade.nix;
in
{
  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      # nix-direnv 3.1.2 (the latest release) logs via >/dev/stderr,
      # which reopens /proc/self/fd/2 and fails (EACCES/ENXIO) when
      # stderr can't be reopened by path — e.g. inside Apple containers,
      # or when driven from Node via socketpair stdio. Fixed on master
      # by https://github.com/nix-community/nix-direnv/pull/753 but not
      # yet in any release, so build the nixpkgs package from a pinned
      # master commit.
      package = overrideUntilUpgrade {
        package = pkgs.nix-direnv;
        version = "3.1.2";
        note = "Drop the master pin in modules/home/direnv.nix if the new version contains nix-direnv PR #753.";
        replacement = pkgs.nix-direnv.override {
          fetchFromGitHub =
            args:
            pkgs.fetchFromGitHub (
              args
              // {
                # master @ 2026-07-05
                rev = "d9d9a251973ce45c28323b27dc9fb50165c82618";
                hash = "sha256-lZVr32AB5aP+rvzdcrbnkyuSxx1mcgLaUi8/eClsvlE=";
              }
            );
        };
      };
    };
    config = import ../shared/programs/direnv.nix;
  };
}
