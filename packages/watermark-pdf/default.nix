{
  python3,
  lib,
}:

python3.pkgs.buildPythonApplication {
  pname = "watermark-pdf";
  version = "0.1.0";
  format = "other";

  src = ./.;

  propagatedBuildInputs = with python3.pkgs; [
    pypdf
    reportlab
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp watermark-pdf.py $out/bin/watermark-pdf
    chmod +x $out/bin/watermark-pdf

    runHook postInstall
  '';

  postFixup = ''
    wrapPythonPrograms
  '';

  meta = {
    description = "Add a watermark to every page of a PDF";
    mainProgram = "watermark-pdf";
  };
}
