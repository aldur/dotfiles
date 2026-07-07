final: prev: {
  beancount-language-server = prev.beancount-language-server.overrideAttrs (old: rec {
    version = "0-unstable-2025-07-10";
    src = prev.fetchFromGitHub {
      owner = "aldur";
      repo = "beancount-language-server";
      rev = "4c3e72f48435dea11793a2f6587fe61ef935207a";
      hash = "sha256-b2DKcICMdl7G46Nqdxe8D23HWpFH4gS8+9Ziqp9d7Ac=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-qy5CH0j9eqaUUFc0zKbtGqp4Z9SLxaUC+vKQFRBLY+k=";
    };
  });
}
