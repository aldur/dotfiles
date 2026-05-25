{ inputs, pkgs, ... }:
let
  inherit (inputs) self;

  flakeName = "current-system-flake";

  editCurrentFlake = pkgs.writeShellScriptBin "edit-current-flake" ''
    set -euo pipefail
    dest="$HOME/flake"
    if [[ -e "$dest" ]]; then
      echo "Error: $dest already exists" >&2
      exit 1
    fi
    cp -rL /etc/${flakeName} "$dest"
    chmod -R u+w "$dest"
    echo "Current system's flake copied to '$dest'."
  '';
in
{
  # Drop a link to the current system configuration flake in to /etc.
  # That way we can tell what configuration built the current
  # system version.
  # NOTE: This will cause a rebuild for any change in the `flake` directory,
  # even if it's just refactoring that wouldn't cause a rebuild.
  # https://discourse.nixos.org/t/nixos-config-flake-store-path-for-run-current-system/24812/6
  environment.etc.${flakeName}.source = self;

  # Script to copy the flake to ~/flake and make it writable.
  home-manager.users.aldur.home.packages = [ editCurrentFlake ];
}
