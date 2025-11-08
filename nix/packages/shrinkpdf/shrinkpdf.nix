{
  stdenv,
  lib,
  fetchFromGitHub,
  ghostscript,
  gawk,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "shrinkpdf";
  version = "unstable-2025-01-08";

  src = fetchFromGitHub {
    owner = "aklomp";
    repo = "shrinkpdf";
    rev = "971c661a4850d20fcd65b954ad157597b6bf3d39";
    hash = "sha256-0wJAr6nFX2o6ciAEwJP0OJoco1zV4kYAOMOdH+5ZXbA=";
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
