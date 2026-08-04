{
  writeArgcApplication,
  qrtool,
}:

writeArgcApplication {
  name = "totp-qr-decode";
  file = ./totp-qr-decode.sh;
  runtimeInputs = [ qrtool ];
}
