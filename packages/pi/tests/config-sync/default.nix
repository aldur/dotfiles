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
  ${lib.getExe nodejs} --test ${./test.mjs}
  touch "$out"
''
