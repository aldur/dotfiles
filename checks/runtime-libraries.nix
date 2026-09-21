{
  runCommand,
  closureInfo,
  python3,
  watermark-pdf,
  split-pdf,
  ripgrep-all,
}:
let
  closure = closureInfo {
    rootPaths = [
      watermark-pdf
      split-pdf
      ripgrep-all
    ];
  };
in
runCommand "runtime-libraries" { nativeBuildInputs = [ python3 ]; } ''
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"
  python3 ${./runtime-libraries.py} ${closure}/store-paths \
    ${watermark-pdf}/bin/watermark-pdf ${split-pdf}/bin/split-pdf ${ripgrep-all}/bin/rga
  touch "$out"
''
