{
  lib,
  writeArgcApplication,
  bash,
  bubblewrap,
  coreutils,
  gnugrep,
  socat,
}:

writeArgcApplication {
  name = "faraday";
  file = ./faraday.sh;
  # bash and socat also run *inside* the sandbox (the wrapper's PATH is
  # inherited across the namespace boundary), so they must be pinned here
  # rather than picked up from the ambient environment.
  runtimeInputs = [
    bash
    bubblewrap
    coreutils
    gnugrep
    socat
  ];
  meta = {
    description = "Run a command with no network access except to explicitly allowed destinations";
    platforms = lib.platforms.linux;
  };
}
