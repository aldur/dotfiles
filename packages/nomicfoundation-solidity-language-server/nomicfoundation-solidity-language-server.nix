{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs-slim,
  nodejs-slim-runtime,
  makeWrapper,
  python3,
  runCommand,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nomicfoundation-solidity-language-server";
  version = "0.9.3";

  src = fetchFromGitHub {
    owner = "NomicFoundation";
    repo = "hardhat-vscode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-IHKYIIkP+iyX0NiyEwrlYcQ4IwhIPp2rS9KRdtMixUA=";
  };

  # Upstream switched to pnpm in 0.9; nix-update refreshes this lockfile cache.
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-Brl3UG/rZKSskhW3IUU1pj5/G2EDzZUJsuVYapweZ80=";
  };

  nativeBuildInputs = [
    nodejs-slim
    pnpm
    pnpmConfigHook
    makeWrapper
  ];

  env = {
    SOLIDITY_GA_SECRET = "dummy-secret";
    SOLIDITY_GOOGLE_TRACKING_ID = "dummy-tracking-id";
    SOLIDITY_SENTRY_DSN = "https://public@sentry.example.com/1";
  };

  buildPhase = ''
    runHook preBuild
    pnpm --filter @nomicfoundation/solidity-language-server run bundle
    runHook postBuild
  '';

  # Deploy only the bundle and its production dependencies, preserving pnpm's
  # links to the native analyzer and dynamically imported Slang packages.
  installPhase = ''
    runHook preInstall
    pnpm --filter @nomicfoundation/solidity-language-server deploy \
      --offline --prod --config.inject-workspace-packages=true "$out/lib/solidity-language-server"
    makeWrapper ${lib.getExe nodejs-slim-runtime} "$out/bin/nomicfoundation-solidity-language-server" \
      --add-flags "$out/lib/solidity-language-server/out/index.js"
    runHook postInstall
  '';

  passthru = {
    # Exercise the deployed package; bundling alone misses broken pnpm links.
    tests.smoke =
      runCommand "solidity-language-server-smoke"
        {
          nativeBuildInputs = [
            python3
            nodejs-slim-runtime
          ];
        }
        ''
          export HOME=$TMPDIR/home
          mkdir -p "$HOME"
          python3 ${./smoke.py} ${finalAttrs.finalPackage}
          touch "$out"
        '';
    # Follows upstream release tags; update-pins also runs the smoke test.
    updatePin = { };
  };
})
