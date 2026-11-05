{ runCommand, faraday, bash, python3, bubblewrap, procps, getent }:
runCommand "faraday-test" {
  nativeBuildInputs = [ faraday bash python3 bubblewrap procps getent ];
} ''
  python3 ${./test.py}
  touch "$out"
''
