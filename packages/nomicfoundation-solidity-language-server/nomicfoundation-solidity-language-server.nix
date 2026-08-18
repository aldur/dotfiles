{
  lib,
  stdenv,
  clang_20,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  libsecret,
  withoutNpmBuildResidue,
}:

withoutNpmBuildResidue (
  buildNpmPackage (finalAttrs: {
    pname = "nomicfoundation-solidity-language-server";
    version = "0.8.29";

    src = fetchFromGitHub {
      owner = "NomicFoundation";
      repo = "hardhat-vscode";
      tag = "v${finalAttrs.version}";
      hash = "sha256-lRujS/Ps56U9q201Fj952huNH+vJZYI/KPjjv/ZjNOk=";
    };

    postPatch = ''
      # NOTE: The tests are somehow run at install time through `npm rebuild`
      # but they ship an old version of hardhat requiring a deprecated node version
      # and makes the build fail.
      rm -rf test/*
    '';

    npmWorkspace = "server";

    npmDepsHash = "sha256-FXp9ii4irSSg+nrHVl8Pcbrr5kuVGU23QSAZHwNDYnk=";

    nativeBuildInputs = [
      pkg-config
    ]
    # https://github.com/NixOS/nixpkgs/pull/451937/files
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ clang_20 ];

    buildInputs = [ libsecret ];

    env = {
      SOLIDITY_GA_SECRET = "dummy-secret";
      SOLIDITY_GOOGLE_TRACKING_ID = "dummy-tracking-id";
      SOLIDITY_SENTRY_DSN = "https://public@sentry.example.com/1";
    };

    # The server entry point is a self-contained esbuild bundle; node_modules
    # is 154M of monorepo dev tooling (eslint, mocha, changesets, ...) the
    # bundle never loads. Only the requires esbuild left external survive:
    # the native solidity-analyzer and the dynamically imported slang, both
    # under the @nomicfoundation scope. (The other externals — bufferutil,
    # utf-8-validate, fsevents — are optional and not even installed.)
    postInstall = ''
      find "$out/lib/node_modules/solidity-language-server-monorepo/node_modules" \
        -mindepth 1 -maxdepth 1 ! -name '@nomicfoundation' -exec rm -rf {} +
    '';

    # Taken from: https://github.com/NixOS/nixpkgs/pull/378937/files
    dontCheckForBrokenSymlinks = true;

    # Follows upstream release tags: nix-update's default, so no extra flags.
    passthru.updatePin = { };
  })
)
