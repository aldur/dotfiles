final: prev: {
  python313Packages = prev.python313Packages.override {
    overrides = pythonFinal: pythonPrev: {
      mlx-lm = pythonPrev.mlx-lm.overrideAttrs (oldAttrs: rec {
        version = "0.28.3";

        src = prev.fetchFromGitHub {
          owner = "ml-explore";
          repo = "mlx-lm";
          tag = "v${version}";
          hash = "sha256-H3LwMx3QFuU6d+ayIN2N+Y3Euv4L09oH0JUZV2Gd7Qw=";
        };

        disabledTestPaths =
          builtins.map (
            path:
            if path == "tests/test_utils_load_model.py" then
              "tests/test_utils.py::TestUtils::test_load_model_with_custom_get_classes"
            else
              path
          ) oldAttrs.disabledTestPaths
          ++ [
            "tests/test_models.py::TestModels::test_gated_delta"
            "tests/test_models.py::TestModels::test_gated_delta_masked"
          ];
      });
      mlx = prev.callPackage ../../packages/mlx/default.nix {
        inherit (pythonFinal) buildPythonPackage fetchPypi;
      };
    };
  };
}
