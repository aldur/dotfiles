{
  runCommand,
  writeShellScriptBin,
  python3,
  bash,
  callPackage,
}:

let
  mockCurl = writeShellScriptBin "curl" ''
    exec ${python3}/bin/python3 ${./test.py} --mock-curl "$@"
  '';
  telegramWithMockCurl = callPackage ./default.nix { curl = mockCurl; };
in
runCommand "telegram-test"
  {
    nativeBuildInputs = [
      bash
      python3
    ];
    TELEGRAM = "${telegramWithMockCurl}/bin/telegram";
  }
  ''
    python3 ${./test.py}
    touch "$out"
  ''
