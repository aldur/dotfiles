{ pkgs }:
let
  inherit (pkgs) lib;
  variant =
    build:
    pkgs.runCommand pkgs.pi.plugins.pi-subagent.name { } ''
      mkdir -p "$out"
      substitute ${./probe.ts} "$out/index.ts" \
        --replace-fail '@subagent@' '${pkgs.pi.plugins.pi-subagent}/index.ts' \
        --replace-fail '@build@' '${build}'
    '';
  pluginA = variant "A";
  pluginB = variant "B";
  wrapper =
    plugin:
    pkgs.pi.override {
      selfUpdates = false;
      plugins = pkgs.pi.plugins // {
        pi-subagent = plugin;
      };
    };
in
pkgs.runCommand "pi-extensions-test" { } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  ${lib.getExe pkgs.python3} ${./check.py} \
    ${lib.getExe (wrapper pluginA)} ${lib.getExe (wrapper pluginB)} \
    ${pluginA}/index.ts ${pluginB}/index.ts
  touch "$out"
''
