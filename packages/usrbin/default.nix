{
  lib,
  writeArgcApplication,
  bubblewrap,
}:

writeArgcApplication {
  name = "usrbin";
  file = ./usrbin.sh;
  # Only bwrap: the wrapper's PATH reaches the child, and every other
  # entry would take precedence over the tools of the caller.
  runtimeInputs = [ bubblewrap ];
  meta = {
    description = "Run a command with the tools of PATH linked under /usr/bin and /bin";
    platforms = lib.platforms.linux;
  };
}
