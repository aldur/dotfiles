{
  buildPythonPackage,
  fetchPypi,

  # dependencies
  mlx,
  numpy,
  transformers,
  protobuf,
  pyyaml,
  jinja2
}:

buildPythonPackage rec {
  pname = "mlx-lm";
  version = "0.25.1";
  format = "wheel";

  src = fetchPypi {
    inherit version format;
    pname = "mlx_lm";
    hash = "sha256-s3I1nyriku8eFl9R9HFX1CETHn+IThegAR+M8ZXwJiU=";
    python = "py3";
    dist = "py3";
  };

  # there is nothing to strip in this package
  dontStrip = true;

  # no Python tests implemented
  doCheck = false;

  dependencies = [
      mlx
      numpy
      transformers
      protobuf
      pyyaml
      jinja2
  ];

  pythonImportsCheck = [
    "mlx_lm"
  ];
}
