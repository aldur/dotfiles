final: prev: {
  beancount-language-server = prev.beancount-language-server.overrideAttrs (old: rec {
    # nixpkgs builds the 1.9.2 tag, which predates upstream's split of
    # providers/completion.rs and the addition of query_cache.rs. The patches
    # below touch both, so the source has to move to their parent commit.
    version = "1.9.2-unstable-2026-08-01";
    src = prev.fetchFromGitHub {
      owner = "polarmutex";
      repo = "beancount-language-server";
      rev = "8035ebd513c5e4c9453045f4d7e8400005fa96e0";
      hash = "sha256-stqCXGCMc/xgznWL1YcgEDTrGh3urtYP5sIRpBFOzvw=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-n08MuquRFQ2v2YVgJJuuJ7CnT8xY5S1Smzzi/Hq7zmQ=";
    };

    # Used patches instead of overriding the source with a fork so that they
    # will keep working (or explicitly breaking) on upstream updates.
    patches = (old.patches or [ ]) ++ [
      (prev.fetchurl {
        url = "https://github.com/aldur/beancount-language-server/commit/6131043ec68b98b2916110c6e66011958dd38981.patch";
        hash = "sha256-4vd0sYjp23MuZhkGBGM7CtHDXX1la8nOXbbbzXuE2ZI=";
      })
      (prev.fetchurl {
        url = "https://github.com/aldur/beancount-language-server/commit/defc5a29ba75eb530bb5371e9c81ced42d33d754.patch";
        hash = "sha256-4X9P6V26J9mDZOSzFM1PQ+EsNowZf+PqLQom1oJd6uk=";
      })
    ];

    # A branch commit rather than a tag; overrideAttrs keeps upstream's
    # meta.position, so nix-update has to be told which file holds the pin.
    passthru = old.passthru or { } // {
      updatePin.args = "--version=branch --override-filename overlays/overrides/beancount-language-server.nix";
    };
  });
}
