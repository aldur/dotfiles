{
  writeArgcApplication,
  uvc-util,
}:

writeArgcApplication {
  name = "c920-defaults";
  file = ./c920-defaults.sh;
  runtimeInputs = [ uvc-util ];
}
