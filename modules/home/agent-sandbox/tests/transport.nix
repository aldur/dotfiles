{
  pkgs,
  lib,
  manifest,
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
  runner = pkgs.writeShellApplication {
    name = "agent-sandbox-transport-test";
    text = ''
      exec ${python}/bin/python3 ${./transport.py} --manifest ${manifest} "$@"
    '';
  };
in
pkgs.runCommand "agent-sandbox-transport-test" { passthru = { inherit runner; }; } ''
  ${lib.getExe runner}
  touch "$out"
''
