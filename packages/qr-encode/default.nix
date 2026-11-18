{
  writeArgcApplication,
  qrtool,
}:

writeArgcApplication {
  name = "qr-encode";
  file = ./qr-encode.sh;
  runtimeInputs = [ qrtool ];
}
