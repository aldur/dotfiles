{
  runCommand,
  python3,
  playwright-mcp,
}:
runCommand "playwright-runtime" { nativeBuildInputs = [ python3 ]; } ''
  export HOME=$TMPDIR/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_CACHE_HOME=$HOME/.cache
  mkdir -p "$HOME"
  python3 ${./playwright-runtime.py} ${playwright-mcp}/bin/playwright-mcp
  touch "$out"
''
