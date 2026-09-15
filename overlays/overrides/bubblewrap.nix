final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  # CVE-2026-87766: use the fixed release until nixpkgs catches up.
  # https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx
  bubblewrap = import ../../utils/override-until-upgrade.nix {
    package = prev.bubblewrap;
    version = "0.11.2";
    note = "Remove the Bubblewrap override once nixpkgs provides >= 0.12.0, which fixes CVE-2026-87766.";
    replacement = prev.bubblewrap.overrideAttrs (old: {
      version = "0.12.0";
      src = prev.fetchFromGitHub {
        owner = "containers";
        repo = "bubblewrap";
        rev = "v0.12.0";
        hash = "sha256-VnhJ5bej3/GTHcU8+AkyR7f3J0KKDuoc94SFxo4grhk=";
      };
      meta = old.meta // {
        license = prev.lib.licenses.lgpl21Plus;
        changelog = "https://github.com/containers/bubblewrap/releases/tag/v0.12.0";
      };
      passthru = (old.passthru or { }) // {
        updatePin.exempt = "Temporary security override; override-until-upgrade forces review when nixpkgs changes version.";
        # The nixpkgs package. A dependent that is cached with it, and only
        # runs bwrap from PATH, builds against it and re-points its wrapper
        # to this package instead (see the codex repack in ../slim.nix).
        unpatched = prev.bubblewrap;
      };
    });
  };
}
