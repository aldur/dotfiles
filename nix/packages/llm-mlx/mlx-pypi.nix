{
  buildPythonPackage,
  fetchPypi,
}:

# WARN: This will likely break if you switch Python version.
buildPythonPackage rec {
  pname = "mlx";
  version = "0.25.2";
  format = "wheel";

  src = fetchPypi {
    inherit pname version format;
    hash = "sha256-JAVaj7qaYmHZTb/THDft51EGx6gyywYJy1tl5+kD4fs=";
    platform = "macosx_15_0_arm64";
    python = "cp312";
    dist = "cp312";
    abi = "cp312";
  };

  # there is nothing to strip in this package
  dontStrip = true;

  # no Python tests implemented
  doCheck = false;

  pythonImportsCheck = [
    "mlx.core"
  ];
}
