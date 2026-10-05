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
    tests.integration = runCommand "pi-config-sync-test" { } ''
      export PI_CONFIG_SYNC_MODULE=${script}/sync.mjs
      export PI_CONFIG_SYNC_PACKAGE=${piPackage}
      export PI_CONFIG_SYNC_LEGACY=${builtins.toFile "pi-legacy-keybindings.json" ''
        {"tui.editor.cursorUp":["up"],"app.session.new":["ctrl+alt+n"]}
      ''}
      ${lib.getExe nodejs} --test ${./test.mjs}
      touch "$out"
    '';
  };
})
