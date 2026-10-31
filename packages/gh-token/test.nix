{ pkgs }:
let
  fakeToken = pkgs.writeShellScriptBin "gh-token" ''
    if [ "''${TOKEN_STATUS:-0}" -ne 0 ]; then
      exit "$TOKEN_STATUS"
    fi
    printf '%s\n' "''${TOKEN_OUTPUT-cached-access}"
  '';
  fakeGh = pkgs.writeShellScriptBin "gh" ''
    exec ${pkgs.python3}/bin/python3 -c '
    import json, os, sys
    print(json.dumps({"token": os.environ.get("GH_TOKEN"), "args": sys.argv[1:]}))
    sys.exit(int(os.environ.get("GH_TEST_STATUS", "0")))
    ' "$@"
  '';
  shortcut = import ../../modules/home/fish/ghs.nix { ghToken = fakeToken; };
  fishFunction = pkgs.writeText "ghs.fish" ''
    function ghs --wraps gh
    ${shortcut.body}
    end
  '';
in
pkgs.runCommand "gh-token-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.requests ]))
      (pkgs.callPackage ./. { })
      pkgs.age
      pkgs.fish
    ];
    GH_TOKEN_AGE = "${pkgs.age}/bin/age";
    GHS_FUNCTION = fishFunction;
    FISH_TEST_BIN = "${fakeGh}/bin";
  }
  ''
    gh-token --help > /dev/null
    fish --no-config --no-execute "$GHS_FUNCTION"
    export PYTHONPATH=${./.}
    python3 ${./test_gh_token.py} -v
    touch "$out"
  ''
