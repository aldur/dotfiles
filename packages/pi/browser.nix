{
  lib,
  writeText,
  writeShellApplication,
  playwright-mcp,
  coreutils,
}:
let
  config = writeText "pi-browser.json" (builtins.toJSON {
    browser = {
      launchOptions.chromiumSandbox = true;
      contextOptions = {
        acceptDownloads = true;
        viewport = {
          width = 1440;
          height = 900;
        };
        locale = "en-US";
        colorScheme = "light";
      };
    };
  });
in
writeShellApplication {
  name = "pi-browser-mcp";
  runtimeInputs = [ coreutils ];
  text = ''
    umask 077
    mkdir -p "$PWD/.pi/browser"
    output=$(mktemp -d "$PWD/.pi/browser/worker-XXXXXXXX")
    exec ${lib.getExe playwright-mcp} \
      --config ${config} --headless --isolated --output-dir "$output"
  '';
}
