{
  runCommand,
  closureInfo,
  python3,
  playwright-lazy,
}:
let
  closure = closureInfo { rootPaths = [ playwright-lazy ]; };
  browserClosure = closureInfo { rootPaths = [ playwright-lazy.browser ]; };
in
runCommand "playwright-runtime" { nativeBuildInputs = [ python3 ]; } ''
  export HOME=$TMPDIR/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_CACHE_HOME=$HOME/.cache
  mkdir -p "$HOME"
  python3 ${./playwright-runtime.py} ${playwright-lazy}/bin/playwright-lazy \
    ${closure}/store-paths ${browserClosure}/store-paths \
    ${playwright-lazy.browser} ${builtins.baseNameOf playwright-lazy.browserExpression}
  touch "$out"
''
