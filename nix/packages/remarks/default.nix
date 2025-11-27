{
  python3,
  python3Packages,
  fetchFromGitHub,
  writeShellApplication,
}:
let

  remarks = python3Packages.buildPythonPackage {
    pname = "remarks";
    version = "unstable-2023-03-08";

    src = fetchFromGitHub {
      owner = "lucasrla";
      repo = "remarks";
      rev = "dc0acf1cd1420239133a4fbdcc17d064b73baeec";
      hash = "sha256-zPTA0PpJgCorRlGab8h/VAN47q7QOZNLKigFi0krDCk=";
    };

    pyproject = true;
    build-system = [ python3Packages.setuptools ];

    nativeBuildInputs = with python3Packages; [
      poetry-core
    ];

    propagatedBuildInputs = with python3Packages; [
      pymupdf
      shapely
    ];

    # Optional dependency for OCR support
    passthru.optional-dependencies = {
      ocr = with python3Packages; [
        ocrmypdf
      ];
    };

    pythonImportsCheck = [ "remarks" ];
  };
  pythonWithRemarks = python3.withPackages (ps: [ remarks ]);
in
writeShellApplication {
  name = "remarks";

  runtimeInputs = [ pythonWithRemarks ];
  text = ''${pythonWithRemarks}/bin/python3 -m remarks "$@"'';
}
