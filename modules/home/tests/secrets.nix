{ pkgs }:
let
  inherit (pkgs) lib;
  keys =
    pkgs.runCommand "test-yubikey-software-keys"
      {
        nativeBuildInputs = [ pkgs.age ];
      }
      ''
        mkdir -p "$out"
        for name in first second unknown fallback; do
          age-keygen -o "$out/$name"
        done
      '';
  plugin = pkgs.writeShellScriptBin "age-plugin-yubikey" ''
    export TEST_KEYS=${keys}
    exec ${pkgs.python3}/bin/python3 ${./secrets-plugin.py} "$@"
  '';
  softwarePlugin = pkgs.writeShellScriptBin "age-plugin-test" ''
    exec ${plugin}/bin/age-plugin-yubikey "$@"
  '';
  identities = map (text: builtins.toFile "test-yubikey-identity" text) [
    ''
      # Recipient: age1yubikey1qq0w0756
        AGE-PLUGIN-YUBIKEY-1QQQVUTDQ
    ''
    ''
      # Recipient: age1yubikey1pqqnqylu
      AGE-PLUGIN-YUBIKEY-1PQ03N3XX
    ''
  ];
  store =
    pkgs.runCommand "test-passage-store"
      {
        nativeBuildInputs = [
          pkgs.age
          plugin
          softwarePlugin
        ];
      }
      ''
        mkdir -p "$out"
        printf 'test password\n' | age \
          -r age1yubikey1qq0w0756 -r age1yubikey1pqqnqylu -o "$out/example.age"
        printf 'fallback password\n' | age -r age1test1qq2y9hht -o "$out/fallback.age"
      '';
  mkModule =
    identities:
    import ../secrets.nix {
      inherit pkgs lib;
      config.programs.aldur.secrets = {
        enable = true;
        inherit identities store;
        extraRecipients = [ ];
        plugins = [
          plugin
          softwarePlugin
        ];
        writableStoreRelative = "secrets/store";
      };
    };
  mkPassage = identities: builtins.head (mkModule identities).config.content.home.packages;
  passage = mkPassage identities;
  ghToken = builtins.elemAt (mkModule identities).config.content.home.packages 1;
  fallbackPassage = mkPassage (
    identities
    ++ [
      (builtins.toFile "test-software-identity" ''
        # Recipient: age1test1qq2y9hht
        AGE-PLUGIN-TEST-1QQK45Y5S
      '')
    ]
  );
in
pkgs.runCommand "passage-yubikey-check"
  {
    nativeBuildInputs = [
      passage
      ghToken
      plugin
      pkgs.age
      pkgs.python3
      pkgs.coreutils
    ];
  }
  ''
    export CONNECTED=first
    passage show example > actual
    printf 'test password\n' > expected
    cmp expected actual

    export CONNECTED=second
    passage show example > actual
    cmp expected actual

    export CONNECTED=first,second
    passage show example > actual
    cmp expected actual

    for connected in none unknown; do
      export CONNECTED="$connected"
      if passage show example > actual 2> error; then
        echo "Decryption succeeded without a configured key" >&2
        exit 1
      fi
      test ! -s actual
      grep -q 'no configured identity' error
    done

    export CONNECTED=none
    export DISCOVERY_STATUS=7
    passage --version > /dev/null
    passage ls > /dev/null
    printf 'new password\n' | passage add --dir "$TMPDIR/writable" new
    unset DISCOVERY_STATUS
    # Use the module's age command to check its temporary identity file.
    selector=$(sed -n 's/^export PASSAGE_AGE=//p' ${passage}/bin/passage)
    identity_file=$(sed -n 's/^export PASSAGE_IDENTITIES_FILE=//p' ${passage}/bin/passage)
    for connected in first second; do
      export CONNECTED="$connected"
      "$selector" -d -i "$identity_file" "$TMPDIR/writable/new.age" > actual
      printf 'new password\n' > expected
      cmp expected actual
    done

    export CONNECTED=first
    export DISCOVERY_STATUS=7
    status=0
    passage show example > actual 2> error || status=$?
    test "$status" -eq 1
    test ! -s actual
    grep -q 'no configured identity' error

    for connected in none first; do
      export CONNECTED="$connected"
      ${fallbackPassage}/bin/passage show fallback > actual
      printf 'fallback password\n' > expected
      cmp expected actual
      if ${fallbackPassage}/bin/passage show example > actual 2> error; then
        echo "Decryption used a key from failed discovery" >&2
        exit 1
      fi
      test ! -s actual
    done
    unset DISCOVERY_STATUS

    printf 'invalid age file' > corrupt.age
    if "$selector" -d -i "$identity_file" corrupt.age > actual 2> error; then
      echo "Decryption accepted an invalid file" >&2
      exit 1
    fi
    test ! -s actual
    test -z "$(find "$TMPDIR" -name identities -o -name connected)"

    export XDG_STATE_HOME="$TMPDIR/gh-state"
    printf 'module-refresh\n' | gh-token init
    credentials="$XDG_STATE_HOME/gh-token/credentials.age"
    for connected in first second; do
      export CONNECTED="$connected"
      "$selector" -d -i "$identity_file" "$credentials" |
        python3 -c 'import json, sys; assert json.load(sys.stdin) == {"refresh_token": "module-refresh"}'
    done

    printf '%s' '{"access_token":"module-access","refresh_token":"module-refresh","expires_at":4102444800}' |
      age -r age1yubikey1qq0w0756 -r age1yubikey1pqqnqylu > "$credentials"
    for connected in first second; do
      export CONNECTED="$connected"
      test "$(gh-token)" = module-access
    done

    touch "$out"
  ''
