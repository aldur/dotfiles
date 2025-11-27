{
  writeShellApplication,
  curl,
  jq,
  coreutils,
}:

writeShellApplication {
  name = "flake-lock-cooldown";

  runtimeInputs = [
    curl
    jq
    coreutils
  ];

  text = builtins.readFile ./flake-lock-cooldown.sh;
}
