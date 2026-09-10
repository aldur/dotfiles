{ pkgs }:
pkgs.runCommand "claude-state-test" { } ''
  ${pkgs.python3}/bin/python3 ${./claude-state.py} ${../claude-state.py} ${pkgs.jq}/bin/jq
  touch "$out"
''
