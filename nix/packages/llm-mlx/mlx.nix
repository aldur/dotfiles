{
  lib,
  fetchFromGitHub,
  buildPythonPackage,
  pybind11,
  cmake,
  nanobind,
  xcbuild,
  zsh,
  blas,
  lapack,
  setuptools,
}:

let
  # static dependencies included directly during compilation
  gguf-tools = fetchFromGitHub {
    owner = "antirez";
    repo = "gguf-tools";
    rev = "af7d88d808a7608a33723fba067036202910acb3";
    hash = "sha256-LqNvnUbmq0iziD9VP5OTJCSIy+y/hp5lKCUV7RtKTvM=";
  };
  nlohmann_json = fetchFromGitHub {
    owner = "nlohmann";
    repo = "json";
    rev = "v3.11.3";
    hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
  };

  nanobind24 = nanobind.overrideAttrs (oldAttrs: rec {
    version = "2.4.0";
    src = fetchFromGitHub {
      owner = "wjakob";
      repo = "nanobind";
      tag = "v${version}";
      hash = "sha256-9OpDsjFEeJGtbti4Q9HHl78XaGf8M3lG4ukvHCMzyMU=";
      fetchSubmodules = true;
    };
  });
in
buildPythonPackage rec {
  pname = "mlx";
  version = "0.25.1";

  src = fetchFromGitHub {
    owner = "ml-explore";
    repo = "mlx";
    rev = "refs/tags/v${version}";
    hash = "sha256-YyjQX8710kfcULHPbOLZsznZVSp66RGQtHXdv3X3vzc=";
  };

  pyproject = true;

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace "/usr/bin/xcrun" "${xcbuild}/bin/xcrun" \
  '';

  dontUseCmakeConfigure = true;

  # updates the wrong fetcher rev attribute
  passthru.skipBulkUpdate = true;

  env = {
    PYPI_RELEASE = version;
    # we can't use Metal compilation with Darwin SDK 11
    CMAKE_ARGS = toString [
      (lib.cmakeBool "MLX_BUILD_METAL" false)
      (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_GGUFLIB" "${gguf-tools}")
      (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_JSON" "${nlohmann_json}")
    ];
  };

  build-system = [
    setuptools
    nanobind24
    cmake
  ];

  nativeBuildInputs = [
    pybind11
    xcbuild
    zsh
    gguf-tools
    nlohmann_json
  ];

  buildInputs = [
    blas
    lapack
  ];
}
