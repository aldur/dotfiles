{
  lib,
  writeArgcApplication,
  bash,
  bubblewrap,
  coreutils,
  getent,
  gnugrep,
  socat,
  callPackage,
}:

let
  package = writeArgcApplication {
    name = "faraday";
    file = ./faraday.sh;
    # bash and socat also run *inside* the sandbox (the wrapper's PATH is
    # inherited across the namespace boundary), so they must be pinned here
    # rather than picked up from the ambient environment.
    runtimeInputs = [
      bash
      bubblewrap
      coreutils
      getent
      gnugrep
      socat
    ];
    passthru.tests.integration = callPackage ./test.nix { faraday = package; };
    meta = {
      description = "Run a command with no network access except to explicitly allowed destinations";
      platforms = lib.platforms.linux;
    };
  };
in
package
