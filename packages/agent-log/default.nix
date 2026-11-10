{
  lib,
  rustPlatform,
  makeWrapper,
  fzf,
  callPackage,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent-log";
  version = "0.1.0";

  # Only the crate. Thus a change to a test or to a local `target/` does not
  # compile the crate again.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  # fzf is the only dependency, because the picker cannot operate without it.
  # The program finds glow, bat and less on the PATH, and continues without
  # them. A dependency on those programs adds 40 MB to the closure, and most
  # machines already have them.
  postInstall = ''
    wrapProgram $out/bin/agent-log \
      --suffix PATH : ${lib.makeBinPath [ fzf ]}
  '';

  # The test uses example files in the format of each agent. Thus a change to
  # a format stops the build, and not the picker.
  passthru.tests.integration = callPackage ./test.nix {
    agent-log = finalAttrs.finalPackage;
  };

  meta = {
    description = "Browse Claude Code, pi and Codex conversations from one picker";
    platforms = lib.platforms.unix;
    mainProgram = "agent-log";
  };
})
