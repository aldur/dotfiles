{
  writeArgcApplication,
  curl,
  jq,
  coreutils,
}:

writeArgcApplication {
  name = "flake-lock-cooldown";
  file = ./flake-lock-cooldown.sh;
  runtimeInputs = [
    curl
    jq
    coreutils
  ];
}
