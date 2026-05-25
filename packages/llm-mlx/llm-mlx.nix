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
      url = "https://github.com/simonw/llm-mlx/pull/20.patch";
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
}
