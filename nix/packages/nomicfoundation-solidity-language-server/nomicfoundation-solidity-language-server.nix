{ buildNpmPackage, fetchFromGitHub, pkg-config, libsecret, }:

buildNpmPackage (finalAttrs: {
  pname = "nomicfoundation-solidity-language-server";
  version = "0.8.25";

  src = fetchFromGitHub {
    owner = "NomicFoundation";
    repo = "hardhat-vscode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-DJm/qv5WMfjwLs8XBL2EfL11f5LR9MHfTT5eR2Ir37U=";
  };

  postPatch = ''
    # NOTE: The tests are somehow run at install time through `npm rebuild`
    # but they ship an old version of hardhat requiring a deprecated node version
    # and makes the build fail.
    rm -rf test/*
  '';

  npmWorkspace = "server";

  npmDepsHash = "sha256-bLP5kVpfRIvHPCutUvTz5MFal6g5fimzXGNdQEhB+Lw=";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ libsecret ];

  env = {
    SOLIDITY_GA_SECRET = "dummy-secret";
    SOLIDITY_GOOGLE_TRACKING_ID = "dummy-tracking-id";
    SOLIDITY_SENTRY_DSN = "dummy-dsn";
  };

  # Taken from: https://github.com/NixOS/nixpkgs/pull/378937/files
  dontCheckForBrokenSymlinks = true;
})
