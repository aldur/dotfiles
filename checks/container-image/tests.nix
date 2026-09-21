{ runCommand, python3 }:
let
  python = python3.withPackages (ps: [ ps.zstandard ]);
in
runCommand "container-size-guard-tests" { } ''
  ${python}/bin/python3 ${./test_guard.py} ${./guard.py}
  touch "$out"
''
