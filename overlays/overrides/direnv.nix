final: prev: {
  direnv = import ../../utils/override-until-upgrade.nix {
    package = prev.direnv;
    version = "2.37.1";
    note = "Review the require_allowed backport and local fixes against the new direnv release (upstream PR #1530).";
    replacement = prev.direnv.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.go-md2man ];
      patches = (old.patches or [ ]) ++ [
        (final.fetchpatch {
          url = "https://github.com/direnv/direnv/commit/02040c767ba64b32a9b5ef2d8d2e00983d6bc958.patch";
          # The optional prune integration depends on unrelated unreleased
          # changes. Approval, revocation and upstream tests are unchanged.
          excludes = [ "internal/cmd/cmd_prune.go" ];
          hash = "sha256-6LdaIRj2m6hDKuYP/80E2/NEm3V70Kdn+cZz/t+tvEo=";
        })
        # Propagate checker failures instead of evaluating empty output.
        ./direnv-require-allowed-fail-closed.patch
        # Keep approvals tied to the actual .envrc for parent/sibling inputs.
        ./direnv-require-allowed-parent-inputs.patch
        # Apply log_format to errors and to `direnv allow` output.
        ./direnv-log-format-everywhere.patch
      ];
    });
  };
}
