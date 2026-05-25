{
  lib,
  stdenv,
  clang_20,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  libsecret,
}:

buildNpmPackage (finalAttrs: {
  pname = "nomicfoundation-solidity-language-server";
  version = "0.8.26";

  src = fetchFromGitHub {
    owner = "NomicFoundation";
    repo = "hardhat-vscode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QXkfPRVQLYmMlhidiLH34wproYpJiVpdZEw1wLRbGAY=";
  };

  postPatch = ''
    # NOTE: The tests are somehow run at install time through `npm rebuild`
    # but they ship an old version of hardhat requiring a deprecated node version
    # and makes the build fail.
    rm -rf test/*
  '';

  npmWorkspace = "server";

  npmDepsHash = "sha256-L3obeOyS4uCsaDYwMJJDJoK8vmWhSqGT2a7I/NsHdwM=";

  nativeBuildInputs = [
    pkg-config
  ]
  # https://github.com/NixOS/nixpkgs/pull/451937/files
  ++ lib.optionals stdenv.isDarwin [ clang_20 ];

  buildInputs = [ libsecret ];

  env = {
    SOLIDITY_GA_SECRET = "dummy-secret";
    SOLIDITY_GOOGLE_TRACKING_ID = "dummy-tracking-id";
    SOLIDITY_SENTRY_DSN = "https://public@sentry.example.com/1";
  };

  # Taken from: https://github.com/NixOS/nixpkgs/pull/378937/files
  dontCheckForBrokenSymlinks = true;
})
