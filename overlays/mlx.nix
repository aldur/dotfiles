# Metal-enabled MLX for Apple Silicon.
#
# nixpkgs builds `mlx` with MLX_BUILD_METAL=OFF (the `metal` shader compiler
# is proprietary and unavailable in the build sandbox), so it does no GPU
# acceleration. Metal support comes from the prebuilt PyPI wheel packaged in
# ../packages/mlx instead.
{
  nixpkgs, # typically nixpkgs-darwin from this flake
  wheelPythonVersion ? null,
  wheelHash ? null,
}:
final: prev:
let
  # The CPython the wheel `hash` corresponds to: by default the python3 of
  # this repo's nixpkgs pin, which is what CI builds against whenever it
  # bumps the hash. Derived, not written down.
  pythonVersion =
    if wheelPythonVersion != null then
      wheelPythonVersion
    else
      nixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system}.python3.pythonVersion;
in
{
  # The interpreter matching the pinned mlx wheel. Consumers build mlx-lm &
  # co. out of this python's package set instead of hardcoding a version — a
  # wheel/Python bump here carries over on their next flake update.
  mlx-python = final."python${prev.lib.replaceStrings [ "." ] [ "" ] pythonVersion}";

  # Use pythonPackagesExtensions, not `python*Packages.override`: the latter
  # only rebinds the top-level `python*Packages` attr and leaves
  # `python3.pkgs` (what `python3.withPackages` reads) untouched, so the
  # overrides would silently not apply there.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pythonFinal: pythonPrev: {
      # mlx-lm is pure Python and resolves its `mlx` dep through this set, so
      # it gets the Metal-enabled wheel, not nixpkgs' mlx. The wheel's CPython
      # tag follows `python`; only its pinned hash needs updating on a Python
      # bump — see ../packages/mlx.
      mlx = prev.callPackage ../packages/mlx/default.nix (
        {
          inherit (pythonFinal) buildPythonPackage fetchPypi python;
          wheelPythonVersion = pythonVersion;
        }
        # null falls through to the pinned hash in ../packages/mlx.
        // prev.lib.optionalAttrs (wheelHash != null) { inherit wheelHash; }
      );
      # mlx-lm >= 0.31 promotes sentencepiece from a test-only to a runtime
      # dependency, but nixpkgs only lists it as a check input — so with
      # checks off it's absent from the runtime closure. Re-add it as a real
      # runtime dep.
      mlx-lm = pythonPrev.mlx-lm.overrideAttrs (oldAttrs: {
        propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [
          pythonFinal.sentencepiece
        ];
      });
    })
  ];
}
