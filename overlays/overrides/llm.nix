final: prev: {
  python313Packages = prev.python313Packages.override {
    overrides = pythonFinal: pythonPrev: {
      mlx-lm = pythonPrev.mlx-lm.overrideAttrs (oldAttrs: rec {
        version = "0.31.3";

        src = prev.fetchFromGitHub {
          owner = "ml-explore";
          repo = "mlx-lm";
          tag = "v${version}";
          hash = "sha256-DPOJfsIucG8mWt4ZKenymCJo/i9Jw+a+iuIygIIYkA8=";
        };

        # Do not seem to work reliably on GH CI
        doCheck = false;
        doInstallCheck = false;
        disabledTestPaths = [ ];

        pythonImportsCheck = [
          "mlx_lm"
        ];
      });
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
    };
  };
}
