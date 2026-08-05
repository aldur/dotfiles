{
  lib,
  python3,
  fetchFromGitHub,
  writeShellApplication,
  runCommand,
  mupdf,
  tesseract,
  tesseract-lite,
}:
let
  # pymupdf's mupdf variant bakes in the tesseract wrapper's path, and
  # the default wrapper bundles every trained language — 1G of OCR
  # models. Both swaps below are same-name copies (equal store path
  # length), so the cached mupdf and pymupdf are repacked byte-exactly
  # rather than rebuilt.
  mupdfOcr = lib.getLib (
    mupdf.override {
      enableOcr = true;
      enableCxx = true;
      enablePython = true;
      enableBarcode = true;
      inherit python3;
    }
  );
  mupdfLite = runCommand mupdfOcr.name { } ''
    cp -a ${mupdfOcr} $out
    chmod -R u+w $out
    find $out -type f -exec sed -i \
      -e "s|${mupdfOcr}|$out|g" \
      -e "s|${tesseract}|${tesseract-lite}|g" {} +
  '';
  pythonForRemarks = python3.override {
    packageOverrides = pyself: pysuper: {
      pymupdf = pyself.toPythonModule (
        runCommand pysuper.pymupdf.name
          {
            # Python envs are assembled from eval-level propagation, and
            # the raw copy would lose it: re-propagate the original
            # inputs with the OCR mupdf swapped for the lite repack (it
            # provides the `mupdf` bindings module).
            propagatedBuildInputs = map (
              d: if (d.outPath or null) == mupdfOcr.outPath then pyself.toPythonModule mupdfLite else d
            ) pysuper.pymupdf.propagatedBuildInputs;
          }
          ''
            cp -a ${pysuper.pymupdf} $out
            chmod -R u+w $out
            find $out -type f -exec sed -i \
              -e "s|${pysuper.pymupdf}|$out|g" \
              -e "s|${mupdfOcr}|${mupdfLite}|g" {} +
          ''
      );
    };
  };

  remarksPkgs = pythonForRemarks.pkgs;
  remarks = remarksPkgs.buildPythonPackage {
    pname = "remarks";
    version = "0-unstable-2023-03-08";

    src = fetchFromGitHub {
      owner = "lucasrla";
      repo = "remarks";
      rev = "dc0acf1cd1420239133a4fbdcc17d064b73baeec";
      hash = "sha256-zPTA0PpJgCorRlGab8h/VAN47q7QOZNLKigFi0krDCk=";
    };

    pyproject = true;
    build-system = [ remarksPkgs.setuptools ];

    nativeBuildInputs = with remarksPkgs; [
      poetry-core
    ];

    propagatedBuildInputs = with remarksPkgs; [
      pymupdf
      shapely
    ];

    # Optional dependency for OCR support
    passthru.optional-dependencies = {
      ocr = with remarksPkgs; [
        ocrmypdf
      ];
    };

    pythonImportsCheck = [ "remarks" ];

    # Tracks its default branch; nothing is tagged upstream.
    passthru.updatePin.args = "--version=branch";
  };
  pythonWithRemarks = pythonForRemarks.withPackages (ps: [ remarks ]);
in
writeShellApplication {
  name = "remarks";

  runtimeInputs = [ pythonWithRemarks ];
  text = ''${pythonWithRemarks}/bin/python3 -m remarks "$@"'';

  # Reachable as `remarks.remarks`: nix-update can't inspect the wrapper
  # (no src), so CI bumps the inner Python package through this path.
  derivationArgs.passthru = { inherit remarks; };
}
