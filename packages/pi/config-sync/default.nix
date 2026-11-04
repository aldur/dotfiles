{
  lib,
  runCommand,
  writeShellScriptBin,
  nodejs,
  pi-coding-agent,
}:
let
  # Resolve proper-lockfile from the same Pi build that will read the files.
  piPackage = "${pi-coding-agent}/lib/node_modules/pi-monorepo";
  script = runCommand "pi-config-sync-script" { } ''
    mkdir -p "$out"
    substitute ${./sync.mjs} "$out/sync.mjs" \
      --replace-fail '@piPackage@' '${piPackage}'
  '';
  helper = writeShellScriptBin "pi-config-sync" ''
    exec ${lib.getExe nodejs} ${script}/sync.mjs "$@"
  '';
in
helper.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.integration = import ../tests/config-sync {
      inherit
        lib
        runCommand
        nodejs
        script
        piPackage
        ;
    };
  };
})
