{
  stdenv,
  lib,
  fetchFromGitHub,
  apple-sdk_15,
}:

stdenv.mkDerivation {
  pname = "uvc-util";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "jtfrey";
    repo = "uvc-util";
    rev = "8110da7025c95eea3096a7181af9a46c0cc7ac37";
    hash = "sha256-deE9zmr+nxEF1tBQAspIR6Uf6lwACfPR+OCK0HvA9Lw=";
  };

  buildInputs = lib.optionals stdenv.isDarwin [
    apple-sdk_15
  ];

  buildPhase = ''
    runHook preBuild
    cd src
    $CC -o uvc-util \
      -framework IOKit \
      -framework Foundation \
      uvc-util.m UVCController.m UVCType.m UVCValue.m
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp uvc-util $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "USB Video Class (UVC) control utility for macOS";
    homepage = "https://github.com/jtfrey/uvc-util";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "uvc-util";
  };
}
