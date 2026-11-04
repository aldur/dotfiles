{
  lib,
  runCommand,
  nodejs,
  script,
  piPackage,
}:
runCommand "pi-config-sync-test" { } ''
  export PI_CONFIG_SYNC_MODULE=${script}/sync.mjs
  export PI_CONFIG_SYNC_PACKAGE=${piPackage}
  export PI_CONFIG_SYNC_LEGACY=${builtins.toFile "pi-legacy-keybindings.json" ''
    {"tui.editor.cursorUp":["up"],"app.session.new":["ctrl+alt+n"]}
  ''}
  ${lib.getExe nodejs} --test ${./test.mjs}
  touch "$out"
''
