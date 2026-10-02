{
  buildPythonPackage,
  fetchPypi,
  fetchurl,

  # build-system
  setuptools,
  setuptools-scm,

  # dependencies
  llm,
  mlx-lm,
}:

buildPythonPackage rec {
  pname = "llm-mlx";
  version = "0.4";
  pyproject = true;

  src = fetchPypi {
    inherit version;
    pname = "llm_mlx";
    hash = "sha256-7jsfsgPJvxj+aks52Kh4eilnQpECuq9R822AkKmyV7o=";
  };

  patches = [
    (fetchurl {
      url = "https://github.com/simonw/llm-mlx/compare/b477833b807143241220f6561742833070d907cc...1019a75da8440acb51c5ccb7b0424a7c1020b137.patch";
      hash = "sha256-J3+Y55MQpNaIuFOvcZL9huWQ/n8W2zEmo/9IkMClAUU=";
    })
  ];

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    llm
    mlx-lm
  ];

  passthru.updatePin = {
    # Follows PyPI releases: nix-update's default, so no extra flags.
    # Build the whole llm env to catch plugin breakage, mirroring
    # the dedicated llm CI job.
    verify = "nix build .#llm";
  };
}
