{
  lib,
  python3,
  fetchPypi,
  fetchFromGitHub,
  stdenvNoCC,
}:
let
  tavily-python = python3.pkgs.buildPythonPackage rec {
    pname = "tavily-python";
    version = "0.8.5";
    pyproject = true;
    src = fetchPypi {
      pname = "tavily_python";
      inherit version;
      hash = "sha256-F5WWXD/+VlSFYkTWN9qoFqTulHrKV9BYi3Mcaedecf4=";
    };
    build-system = [ python3.pkgs.setuptools ];
    dependencies = with python3.pkgs; [
      requests
      tiktoken
      httpx
    ];
    pythonImportsCheck = [ "tavily" ];
    passthru.updatePin = { };
  };
  skills = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "tavily-skills";
    version = "2.3.0";
    src = fetchFromGitHub {
      owner = "tavily-ai";
      repo = "skills";
      tag = "v${finalAttrs.version}";
      hash = "sha256-gSalwSyz0TRBgfm5s+1o/C1mnNBsFG02gg1CoxwdXfI=";
    };
    installPhase = ''
      mkdir -p "$out"
      cp -r skills/core/tavily-search "$out/"
    '';
    passthru.updatePin = { };
  });
in
python3.pkgs.buildPythonApplication rec {
  pname = "tavily-cli";
  version = "0.2.1";
  pyproject = true;
  src = fetchPypi {
    pname = "tavily_cli";
    inherit version;
    hash = "sha256-VKmPyrBaYKP+hnfTRe7glwDGOGREhx5/h+EYZZATl1c=";
  };
  build-system = [ python3.pkgs.hatchling ];
  dependencies = [
    tavily-python
  ]
  ++ (with python3.pkgs; [
    certifi
    click
    httpx
    packaging
    psutil
    requests
    rich
    urllib3
  ]);
  nativeCheckInputs = [ python3.pkgs.pytestCheckHook ];
  # Click 8.3 needs an unset default for an optional option value.
  postPatch = ''
    substituteInPlace tavily_cli/common.py \
      --replace-fail 'is_flag=False, flag_value="", default=None,' 'is_flag=False, flag_value="",'
  '';
  enabledTestPaths = [
    "tests/test_output.py"
    "tests/test_oauth.py"
  ];
  pythonImportsCheck = [ "tavily_cli.cli" ];
  passthru = {
    inherit tavily-python skills;
    updatePin = { };
    absentFromNixpkgs = "tavily-cli";
  };
  meta = {
    description = "Search the web and extract page content with Tavily";
    homepage = "https://github.com/tavily-ai/tavily-cli";
    license = lib.licenses.mit;
    mainProgram = "tvly";
  };
}
