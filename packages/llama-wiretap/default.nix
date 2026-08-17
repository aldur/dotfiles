{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs-slim,
  callPackage,
}:

# nodejs-slim rather than nodejs: the script is stdlib-only (http, zlib, fs),
# so npm and the headers a build toolchain would read are dead weight. It is
# also the runtime `pi` already pulls in, which is the only place this proxy
# is any use.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "llama-wiretap";
  version = "0.1.0";

  src = builtins.path {
    path = ./.;
    name = "llama-wiretap";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec $out/bin
    for tool in llama-wiretap llama-wiretap-show; do
      cp ${finalAttrs.src}/$tool.mjs $out/libexec/$tool.mjs
      makeWrapper ${nodejs-slim}/bin/node $out/bin/$tool \
        --add-flags $out/libexec/$tool.mjs
    done

    runHook postInstall
  '';

  # Proxies a streaming completion over both a TCP and a Unix socket and
  # checks the transcript against what the upstream actually received.
  # Reachable as `llama-wiretap.tests`, so the flake check finds it without
  # being told it exists.
  passthru.tests.integration = callPackage ./test.nix {
    llama-wiretap = finalAttrs.finalPackage;
  };

  meta = {
    description = "Logging reverse proxy between a coding agent and an OpenAI-compatible inference server";
    platforms = lib.platforms.unix;
    mainProgram = "llama-wiretap";
  };
})
