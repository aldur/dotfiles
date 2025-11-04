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
      mlx = pythonPrev.mlx.overrideAttrs (oldAttrs: rec {
        version = "0.29.3";

        src = prev.fetchFromGitHub {
          owner = "ml-explore";
          repo = "mlx";
          tag = "v${version}";
          hash = "sha256-QcT+D0Zc9OqaLXcgUO9BKgrThIIle2b5Ajb0sk/8HGA=";
        };

        patches = [
          (prev.replaceVars ./llm-darwin-build-fixes.patch {
            sdkVersion = prev.apple-sdk_15.version;
          })
        ];

        postPatch = oldAttrs.postPatch + ''
          substituteInPlace pyproject.toml \
          --replace-fail "cmake>=3.25,<4.1" "cmake>=3.25"
        '';
      });
    };
  };
}
