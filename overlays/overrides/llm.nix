final: prev: {
  # Use pythonPackagesExtensions, not `python*Packages.override`: the latter
  # only rebinds the top-level `python*Packages` attr and leaves
  # `python3.pkgs` (what `python3.withPackages` in llmWithPlugins reads)
  # untouched, so the overrides silently didn't apply there.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pythonFinal: pythonPrev: {
      mlx-lm = pythonPrev.mlx-lm.overrideAttrs (oldAttrs: {
        # mlx-lm >= 0.31 promotes sentencepiece from a test-only to a runtime
        # dependency, but nixpkgs only lists it as a check input — so with
        # checks off it's absent from the runtime closure. Re-add it as a real
        # runtime dep.
        propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [
          pythonFinal.sentencepiece
        ];
      });
      # Metal support comes from this prebuilt Apple-Silicon mlx wheel (mlx-lm
      # is pure Python and imports it). mlx-lm resolves its `mlx` dep through
      # this set, so it gets the Metal-enabled wheel, not nixpkgs' mlx.
      mlx = prev.callPackage ../../packages/mlx/default.nix {
        inherit (pythonFinal) buildPythonPackage fetchPypi;
      };
      accelerate = pythonPrev.accelerate.overridePythonAttrs (_: {
        # https://github.com/NixOS/nixpkgs/issues/420372
        doCheck = false;
      });
      peft = pythonPrev.peft.overridePythonAttrs (oldAttrs: {
        disabledTestPaths = oldAttrs.disabledTestPaths ++ [
          "tests/test_vblora.py::TestVBLoRA::test_save_load"
          "tests/test_vblora.py::TestVBLoRA::test_resume_training_model_with_topk_weights"
        ];
      });
    })
  ];
}
