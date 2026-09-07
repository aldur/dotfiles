{
  writeArgcApplication,
  curl,
  gnused,
  callPackage,
}:

writeArgcApplication {
  name = "telegram";
  file = ./telegram.sh;
  runtimeInputs = [
    curl
    gnused
  ];
  passthru.tests.integration = callPackage ./test.nix { };
}
