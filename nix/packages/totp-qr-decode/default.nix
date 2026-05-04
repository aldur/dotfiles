{
  stdenv,
  python3,
}:
let
  pythonWithPkgs = python3.withPackages (ps: [ ps.opencv4 ]);
in
stdenv.mkDerivation {
  pname = "totp-qr-decode";
  version = "0.1.0";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 totp-qr-decode.py $out/bin/totp-qr-decode
    substituteInPlace $out/bin/totp-qr-decode \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonWithPkgs}/bin/python3'
    runHook postInstall
  '';
}
