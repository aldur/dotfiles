{
  stdenvNoCC,
  agent-log,
  python3,
  fzf,
}:

stdenvNoCC.mkDerivation {
  name = "agent-log-test";
  nativeBuildInputs = [
    agent-log
    python3
    fzf
  ];
  buildCommand = ''
    python3 ${./tests.py} "$(command -v agent-log)"
    mkdir -p $out
    touch $out/passed
  '';
}
