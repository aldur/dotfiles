{ pkgs }:
let
  browser = pkgs.writeShellScriptBin "chrome-headless-shell" ''
    printf 'browser:%s\n' "$*"
  '';
  installer = pkgs.writeShellScriptBin "nix-build" ''
    echo install >> "$LAZY_TEST_LOG"
    [ "''${LAZY_TEST_FAIL:-0}" = 0 ] || exit 1
    ${pkgs.coreutils}/bin/sleep 0.3
    ${pkgs.coreutils}/bin/ln -s ${browser} "''${@: -1}"
  '';
  launcher = pkgs.callPackage ../overlays/playwright-lazy.nix {
    nix = installer;
    browserExpression = pkgs.writeText "browser-fixture.nix" "{}";
  };
in
pkgs.runCommand "playwright-lazy-test" {
  nativeBuildInputs = [ pkgs.python3 ];
  # Run on the CI host: installation needs a Nix daemon.
  passthru.install = pkgs.writeShellApplication {
    name = "check-playwright-install";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./playwright-install.py} \
        ${pkgs.playwright-lazy.browserLauncher} ${pkgs.playwright-lazy.browser}
    '';
  };
} ''
  python3 ${./playwright-lazy.py} ${launcher}
  touch "$out"
''
