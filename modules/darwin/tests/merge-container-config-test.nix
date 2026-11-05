{ runCommand, python3 }:
let
  python = python3.withPackages (ps: [ ps.tomlkit ]);
in
runCommand "merge-container-config-test" { } ''
  ${python}/bin/python3 ${./merge-container-config.py} ${../merge-container-config.py}
  touch "$out"
''
