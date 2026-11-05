{ runCommand, faraday, bash, socat, procps, util-linux, getent }:
runCommand "faraday-test" {
  nativeBuildInputs = [ faraday bash socat procps util-linux getent ];
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  bash ${./test.sh}
  touch "$out"
''
