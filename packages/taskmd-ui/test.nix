{ runCommand, python3, taskmd-ui }:
let
  python = python3.withPackages (ps: [ ps.pyyaml ]);
in
runCommand "taskmd-ui-smoke" { } ''
  ${python}/bin/python3 ${./test.py} ${taskmd-ui}/bin/taskmd-ui
  touch "$out"
''
