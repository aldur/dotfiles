{
  pkgs ? import <nixpkgs> { },
}:

let
  # Use Python 3.13 specifically because the Solidity docs require the sphinx_syntax extension,
  # which only supports Python 3.12+
  python = pkgs.python313;

  # Build pygments-lexer-solidity as a proper Python package
  pygments-lexer-solidity = python.pkgs.buildPythonPackage rec {
    pname = "pygments-lexer-solidity";
    version = "0.7.0";
    format = "setuptools";

    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-o0f9lpgYODMbbZiw+JF3aQiklAbTQ/8qQKahyEdak1A=";
    };

    propagatedBuildInputs = with python.pkgs; [ pygments ];

    pythonImportsCheck = [ "pygments_lexer_solidity" ];
  };

  # Build syntax-diagrams as a proper Python package
  syntax-diagrams = python.pkgs.buildPythonPackage rec {
    pname = "syntax-diagrams";
    version = "1.0.0.post1";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/cd/e6/9165cc52e55b8cac198b5973931332c12fd3cf22de3f8e8d558e194e403d/syntax_diagrams-${version}.tar.gz";
      sha256 = "sha256-PdyZXQiOlmpVyieq2B+QMx4IOpufEasirziuqOEy7sA=";
    };

    build-system = with python.pkgs; [
      setuptools
      setuptools-scm
    ];

    dependencies = with python.pkgs; [
      grapheme
      wcwidth
    ];

    pythonImportsCheck = [ "syntax_diagrams" ];
  };

  # Build sphinx-syntax as a proper Python package
  sphinx-syntax = python.pkgs.buildPythonPackage rec {
    pname = "sphinx-syntax";
    version = "1.0.1";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/2d/88/66991eeb5e884b31e6c3a5a56b24f7e0b7d14c1cccf5a37af206501ccead/sphinx_syntax-${version}.tar.gz";
      sha256 = "sha256-EHxboV+QArgKI3mK2BAU7cMPj9CgpM1NWfaQdI2gFSk=";
    };

    build-system = with python.pkgs; [
      setuptools
      setuptools-scm
    ];

    dependencies = with python.pkgs; [
      sphinx
      pyyaml
      antlr4-python3-runtime
      syntax-diagrams
    ];
  };

  # Build doc2dash as a proper Python package
  doc2dash = python.pkgs.buildPythonPackage rec {
    pname = "doc2dash";
    version = "3.1.0";
    pyproject = true;

    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-N/YcjY9qlV0kZrnAc+sr/0TMVDUr+BevtIo6yK721ZQ=";
    };

    build-system = with python.pkgs; [
      hatchling
      hatch-vcs
      hatch-fancy-pypi-readme
    ];

    dependencies = with python.pkgs; [
      beautifulsoup4
      lxml
      click
      attrs
      rich
    ];

    pythonImportsCheck = [ "doc2dash" ];
  };

  # Create a Python environment with all required packages
  pythonEnv = python.withPackages (
    ps: with ps; [
      sphinx
      sphinx-rtd-theme
      pygments
      pyyaml
      beautifulsoup4
      lxml
      setuptools
      # Our custom packages
      pygments-lexer-solidity
      sphinx-syntax
      doc2dash
    ]
  );
in
pkgs.stdenv.mkDerivation {
  pname = "solidity-dash-docset";
  version = "0.8.31-pre.1";

  src = pkgs.fetchFromGitHub {
    owner = "argotorg";
    repo = "solidity";
    rev = "v0.8.31-pre.1";
    sha256 = "sha256-2ecE3EkG94fB4ju3yH0nSkULlkCn+UOqTYMf9dkFKH8=";
  };

  nativeBuildInputs = [
    pythonEnv
    pkgs.sqlite
  ];

  buildPhase = ''
    runHook preBuild

    pushd docs

    # Build the Sphinx documentation
    sphinx-build -nW -b html -d _build/doctrees . _build/html

    # Remove the navigation sidebar from all HTML files to make them cleaner for Dash
    find _build/html -name '*.html' -type f -exec python3 ${./clean_html.py} {} \;

    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    cd docs/_build/html

    # Convert to Dash docset using doc2dash
    doc2dash -n Solidity -d $out .

    # Fix Guide-type entries to point to the main heading anchor
    python3 ${./fix_guide_anchors.py} "$out/Solidity.docset"

    runHook postInstall
  '';
}
