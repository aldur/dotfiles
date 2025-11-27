{
  stdenv,
  lib,
  fetchFromGitHub,
  ghostscript,
  gawk,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "shrinkpdf";
  version = "unstable-2025-01-08";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "shrinkpdf";
    rev = "d8e4aca8a4caebcc1ef0f569e6651c8dc5964334";
    hash = "sha256-URS7V00TJgrUiRC7YAaCrcmONgC5+xaHS6QPE6wv+Jo=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    ghostscript
    gawk
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp shrinkpdf.sh $out/bin/shrinkpdf
    chmod +x $out/bin/shrinkpdf

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/shrinkpdf \
      --prefix PATH : ${
        lib.makeBinPath [
          ghostscript
          gawk
        ]
      }
  '';
}
