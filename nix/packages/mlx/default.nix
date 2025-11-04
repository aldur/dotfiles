{
  lib,
  stdenv,
  fixDarwinDylibNames,
  buildPythonPackage,
  fetchPypi,
}:
let
  version = "0.29.3";
  format = "wheel";
  platform = "macosx_15_0_arm64";

  mlx_metal = buildPythonPackage rec {
    inherit version format;
    pname = "mlx_metal";

    src = fetchPypi {
      inherit
        pname
        version
        format
        platform
        ;
      hash = "sha256-EGYW9/glhRBDxT09wYaWXAA5hdqcu25cA081EI/B/Cc=";
      python = "py3";
      dist = "py3";
    };

    dontStrip = true;
    doCheck = false;
  };
in
# https://github.com/NixOS/nixpkgs/blob/b3d51a0365f6695e7dd5cdf3e180604530ed33b4/pkgs/development/python-modules/mlx/default.nix#L78
#
# Building `mlx` with `metal` support in macOS requires a sandbox escape.
# The version shipped in `nixpkgs` does not do any acceleration.
#
# WARN: This will likely break when switching Python versions.
buildPythonPackage rec {
  inherit version format;
  pname = "mlx";

  src = fetchPypi {
    inherit
      pname
      version
      format
      platform
      ;
    hash = "sha256-7ArvMR+rEMtfLCdK+m7fbEgmNglqX3iGq6Q2dkVKpGI=";
    python = "cp313";
    dist = "cp313";
    abi = "cp313";
  };

  nativeBuildInputs = [
    fixDarwinDylibNames
  ];

  # After pip installs the mlx wheel, extract mlx_metal and copy its lib directory
  # NOTE: This is not copying any other file, e.g. headers.
  postInstall = ''
    libdir=${mlx_metal}/lib/python3.13/site-packages/mlx
    cp -r "$libdir/lib" "$out/lib/python3.13/site-packages/mlx/"
  '';

  postFixup = lib.optionalString stdenv.isDarwin ''
    libdir="$out/lib/python3.13/site-packages/mlx"

    if [ -f "$libdir/lib/libmlx.dylib" ]; then
      for so in "$libdir"/*.so; do
        if [ -f "$so" ] && [ "$so" != "$libdir/core.cpython-313-darwin.so" ]; then
          install_name_tool -add_rpath "$libdir/lib" "$so" 2>/dev/null || true
          install_name_tool -change @rpath/libmlx.dylib "$libdir/lib/libmlx.dylib" "$so" 2>/dev/null || true
        fi
      done
      exit 0
    fi

    echo "ERROR: libmlx.dylib not found after copying from mlx_metal"
    exit 1
  '';

  dontStrip = true;
  doCheck = false;

  pythonImportsCheck = [
    "mlx.core"
  ];

  meta = {
    platforms = lib.platforms.darwin;
    broken = !stdenv.isDarwin || !stdenv.isAarch64;
  };
}
