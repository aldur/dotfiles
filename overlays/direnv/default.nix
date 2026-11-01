{ self }:
final: _prev:
let
  package = final.callPackage (self.inputs.nixpkgs-unstable + "/pkgs/by-name/di/direnv/package.nix") { };
in
{
  direnv = import ../../utils/override-until-upgrade.nix {
    inherit package;
    version = "2.39.0";
    note = "Review the local require_allowed fixes against the new direnv release.";
    replacement = package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        # Propagate checker failures instead of evaluating empty output.
        ./require-allowed-fail-closed.patch
        # Keep approvals tied to the actual .envrc for parent/sibling inputs.
        ./require-allowed-parent-inputs.patch
        # Apply log_format to errors and to `direnv allow` output.
        ./log-format-everywhere.patch
        # Bound approval messages; keep full details available on demand.
        ./concise-approvals.patch
      ];
      postCheck = (old.postCheck or "") + ''
        ${final.python3}/bin/python3 ${./concise-approvals_test.py} "$PWD/direnv"
      '';
    });
  };
}
