{
  stdenv,
  lib,
  fetchFromGitHub,
  ghostscript,
  gawk,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "shrink-pdf";
  version = "1.2-unstable-2026-10-20";

  src = fetchFromGitHub {
    owner = "aklomp";
    repo = "shrinkpdf";
    rev = "cd157c2838607317ace3ad43821c29c0815c19ab";
    hash = "sha256-yn7QW/hrOC+GWFFvLHYKCZLoXZJnqm1nvIgjAxGTYEc=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    ghostscript
    gawk
  ];

  dontBuild = true;

  # Upstream only accepts -h; teach it --help too (used by aldurs-tools' preview).
  postPatch = ''
    helpPatch=$(cat <<'PATCH'
    # Allow --help as a synonym for -h.
    __n=$#
    __i=0
    while [ $__i -lt $__n ]; do
        case "$1" in --help) set -- "$@" -h ;; *) set -- "$@" "$1" ;; esac
        shift
        __i=$((__i + 1))
    done

    while getopts ':hgo:r:t:' flag; do
    PATCH
    )
    substituteInPlace shrinkpdf.sh --replace-fail \
      "while getopts ':hgo:r:t:' flag; do" \
      "$helpPatch"

    # Use the canonical name in usage output instead of the wrapped store path.
    substituteInPlace shrinkpdf.sh --replace-quiet 'usage "$0"' 'usage "shrink-pdf"'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp shrinkpdf.sh $out/bin/shrink-pdf
    chmod +x $out/bin/shrink-pdf

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/shrink-pdf \
      --prefix PATH : ${
        lib.makeBinPath [
          ghostscript
          gawk
        ]
      }
  '';

  # Tracks its default branch; nothing is tagged upstream.
  passthru.updatePin.args = "--version=branch";
}
