final: prev: {
  # Use pythonPackagesExtensions, not `python*Packages.override`: the latter
  # only rebinds the top-level `python*Packages` attr and leaves
  # `python3.pkgs` (what `python3.withPackages` in llmWithPlugins reads)
  # untouched, so the overrides silently didn't apply there.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pythonFinal: pythonPrev: {
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
