{ pkgs, pi }:
pkgs.runCommand "pi-browser-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  python3 ${./check.py} ${pkgs.lib.getExe (pi.override { selfUpdates = false; })} "$TMPDIR/check"
  touch "$out"
''
