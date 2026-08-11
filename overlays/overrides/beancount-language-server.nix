final: prev: {
  beancount-language-server = prev.beancount-language-server.overrideAttrs (old: rec {
    # Build the `next` branch of the aldur fork. The branch carries the
    # patches that this overlay applied before.
    version = "1.9.2-unstable-2026-08-10";
    src = prev.fetchFromGitHub {
      owner = "aldur";
      repo = "beancount-language-server";
      rev = "8f6975913524985e2695190eb052d9a59839d6fc";
      hash = "sha256-ikNu4I+shYiYsuC8/u6hYXXwwVxaJ/Y5QOtjMMKS+qk=";
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
