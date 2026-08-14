{
  writeArgcApplication,
  curl,
  gnused,
}:

writeArgcApplication {
  name = "telegram";
  file = ./telegram.sh;
  runtimeInputs = [
    curl
    gnused
  ];
}
