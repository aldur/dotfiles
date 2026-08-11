{
  writeArgcApplication,
  coreutils,
  qrtool,
}:

writeArgcApplication {
  name = "totp-qr-decode";
  file = ./totp-qr-decode.sh;
  runtimeInputs = [
    coreutils
    qrtool
  ];
}
