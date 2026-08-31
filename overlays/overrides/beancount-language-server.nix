final: prev: {
  beancount-language-server = prev.beancount-language-server.overrideAttrs (old: rec {
    # Build the `next` branch of the aldur fork. The branch carries the
    # patches that this overlay applied before.
    version = "1.9.2-unstable-2026-08-24";
    src = prev.fetchFromGitHub {
      owner = "aldur";
      repo = "beancount-language-server";
      rev = "172668106182960c12d183dfaa56b3cd1252d640";
      hash = "sha256-hriqCkFWZH1LurGPQ8If4S/v0zonkElVYuTdUIgtlPA=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-/RAAo4aR2ttTNXlg/mNjNFkE73SIys5QMX3F8ql2cgw=";
    };

    # A branch commit rather than a tag; overrideAttrs keeps upstream's
    # meta.position, so nix-update has to be told which file holds the pin.
    passthru = old.passthru or { } // {
      updatePin.args = "--version=branch=next --override-filename overlays/overrides/beancount-language-server.nix";
    };
  });
}
