{
  writeArgcApplication,
  writeShellScriptBin,
  jq,
  python3,
  runCommand,
}:

let
  cooldown = writeShellScriptBin "update-pins-cooldown" ''
    exec ${python3.interpreter} ${./cooldown.py} "$@"
  '';
in
writeArgcApplication {
  name = "update-pins";
  file = ./update-pins.sh;
  runtimeInputs = [
    jq
    cooldown
  ];
  meta.description = "Run the `updatePins` bump legs of the flake in the current directory";
  passthru.tests.cooldown = runCommand "update-pins-cooldown-test" { } ''
    cd ${./.}
    ${python3.interpreter} test_cooldown.py
    touch $out
  '';
}
