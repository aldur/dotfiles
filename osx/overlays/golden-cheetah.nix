(final: prev: {
  golden-cheetah = prev.golden-cheetah.overrideAttrs (old: {
    version = "V3.7-DEV (5002)";
    src = prev.fetchFromGitHub {
      owner = "GoldenCheetah";
      repo = "GoldenCheetah";
      rev = "baa44965e36a5fb9bd44c0a6d8e51eec2347a558";
      hash = "sha256-xjp4ipE/maho6zojuGZ6ClT2oT8qS8STCemOHYHviKA=";
    };
  });
})
