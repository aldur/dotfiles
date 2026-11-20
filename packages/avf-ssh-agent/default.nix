{
  lib,
  buildGoModule,
  callPackage,
}:

# The guest end of the SSH agent that an Android app serves from a YubiKey:
# a pipe between an ssh-agent socket and the app. The app connects to the
# bridge through the port forwarding of the Terminal app, with mutual TLS.
# ./app/core has the agent itself.
buildGoModule (finalAttrs: {
  pname = "avf-ssh-agent";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./bridge;
    fileset = ./bridge;
  };

  # Only the standard library.
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  passthru.core = callPackage ./app/core { };

  meta = {
    description = "Bridge between an ssh-agent socket and the Android app that holds the YubiKey";
    platforms = lib.platforms.linux;
    mainProgram = "avf-ssh-agent";
  };
})
