{
  lib,
  stdenv,
  fixDarwinDylibNames,
  buildPythonPackage,
  fetchPypi,
  python,
  # The CPython the wheel `wheelHash` was fetched for; supplied by the
  # overlay, which derives it from this repo's own nixpkgs pin.
  wheelPythonVersion,
  # Hash of the cp-specific mlx wheel for `wheelPythonVersion`. Defaults to
  # the pin this repo maintains (bumped by nix-update); overridable together
  # with `python`/`wheelPythonVersion` to run a newer CPython than we ship.
  wheelHash ? "sha256-ft6+3r4/Bs5HGvXLZGinQ+698vg6Q/hlHi3iDlptbmI=",
}:
let
  version = "0.32.1";
  format = "wheel";
  platform = "macosx_15_0_arm64";

  # The mlx wheel is CPython-specific; follow whatever interpreter this
  # package set is built for, e.g. "313" -> "cp313". PyPI ships wheels for
  # every current CPython, but each has its own hash — `wheelHash` matches
  # exactly one of them, the one for wheelPythonVersion. The assert turns an
  # interpreter/hash mismatch into a readable error instead of a failed
  # fetch. (The mlx_metal wheel is py3-none: one hash fits all interpreters.)
  pyShort = lib.replaceStrings [ "." ] [ "" ] python.pythonVersion;
  cpTag = "cp${pyShort}";

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
      hash = "sha256-oC1cZy9VkrKaius8eTkZ+D7rMq044MgUwJ/m5jKhR9M=";
      python = "py3";
      dist = "py3";
    };

    dontStrip = true;
    doCheck = false;

    # Shares `version` with mlx; bumped in lockstep by the parent's
    # `--subpackage mlx_metal` nix-update flag, not as a leg of its own.
    passthru.updatePin.exempt = "bumped with mlx via --subpackage";
  };
in
# https://github.com/NixOS/nixpkgs/blob/b3d51a0365f6695e7dd5cdf3e180604530ed33b4/pkgs/development/python-modules/mlx/default.nix#L78
#
# Building `mlx` with `metal` support in macOS requires a sandbox escape.
# The version shipped in `nixpkgs` does not do any acceleration.
assert lib.assertMsg (python.pythonVersion == wheelPythonVersion)
  "mlx: the wheel hash is for CPython ${wheelPythonVersion}, but this package set uses ${python.pythonVersion}; use the `mlx-python` interpreter from the overlay, or build the overlay for another CPython via `lib.mkMlxOverlay`";
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
    hash = wheelHash;
    python = cpTag;
    dist = cpTag;
    abi = cpTag;
  };

  nativeBuildInputs = [
    fixDarwinDylibNames
  ];

  # After pip installs the mlx wheel, copy lib/ and include/ from mlx_metal.
  # The runtime loads lib/ (libmlx.dylib, mlx.metallib). Native extensions,
  # for example the mtplx paged-attention module, compile against include/.
  postInstall = ''
    metaldir=${mlx_metal}/${python.sitePackages}/mlx
    cp -r "$metaldir/lib" "$metaldir/include" "$out/${python.sitePackages}/mlx/"
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    libdir="$out/${python.sitePackages}/mlx"

    if [ -f "$libdir/lib/libmlx.dylib" ]; then
      for so in "$libdir"/*.so; do
        if [ -f "$so" ] && [ "$so" != "$libdir/core.cpython-${pyShort}-darwin.so" ]; then
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

  # The mlx wheel declares a runtime dependency on `mlx-metal`, which we don't
  # install as a separate Python package (both wheels would collide on the
  # `mlx/` namespace). Instead its `lib/` and `include/` are vendored in via
  # postInstall above, so the runtime-deps check has nothing to find and would
  # fail spuriously.
  dontCheckRuntimeDeps = true;

  pythonImportsCheck = [
    "mlx.core"
  ];

  passthru = {
    # Exposed so nix-update's `--subpackage mlx_metal` can reach it.
    inherit mlx_metal;
    updatePin = {
      # nix-update can't infer PyPI from a *wheel* fetchPypi src (only the
      # `mirror://pypi` sdist form), so point it at the project explicitly.
      # Both wheels share `version`; `--subpackage` keeps the mlx_metal hash
      # in sync.
      args = "--url mirror://pypi/m/mlx --subpackage mlx_metal";
      # Build the whole llm env to catch mlx-lm/plugin breakage, mirroring
      # the llm-mlx leg.
      verify = "nix build .#llm";
    };
  };

  meta = {
    platforms = lib.platforms.darwin;
    broken = !stdenv.hostPlatform.isDarwin || !stdenv.hostPlatform.isAarch64;
  };
}
