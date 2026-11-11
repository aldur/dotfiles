{
  pkgs,
  lib,
  config,
  ...
}:
# age-based password store via passage (https://github.com/FiloSottile/passage),
# with public identity stubs and encrypted secrets baked into the Nix store.
let
  cfg = config.programs.aldur.secrets;

  # Read and validate before generating store files. Passing the paths to
  # runCommand would copy them into the store before its guard could run.
  # A key included in a flake source is already copied before module evaluation.
  identities = map (
    path:
    let
      text = builtins.readFile path;
      recipient = lib.findFirst builtins.isList null (builtins.split "(age1[a-z0-9]+)" text);
    in
    if lib.hasInfix "AGE-SECRET-KEY-1" text then
      throw "secrets.nix: identities must contain public identity stubs, never plaintext age secret keys"
    else if recipient == null then
      throw "secrets.nix: no 'age1...' recipient found in identity: ${toString path}"
    else
      {
        inherit text;
        recipient = builtins.head recipient;
      }
  ) cfg.identities;

  identitiesFile = pkgs.writeText "age-identities" (
    lib.concatMapStrings (identity: identity.text + "\n") identities
  );

  passageAge = pkgs.writeShellApplication {
    name = "passage-age";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
    ]
    ++ cfg.plugins;
    text = ''
      args=("$@")
      ${lib.optionalString
        (lib.any (identity: lib.hasInfix "AGE-PLUGIN-YUBIKEY-" identity.text) identities)
        ''
          decrypt=false
          for arg in "$@"; do
            case "$arg" in
              -d | --decrypt) decrypt=true ;;
            esac
          done
          if "$decrypt"; then
            identity_dir=$(mktemp -d)
            trap 'rm -rf "$identity_dir"' EXIT
            if ! age-plugin-yubikey --identity > "$identity_dir/connected"; then
              : > "$identity_dir/connected"
            fi
            awk '
              FILENAME == ARGV[1] { connected[$1] = 1; next }
              $1 ~ /^AGE-PLUGIN-YUBIKEY-/ {
                if ($1 in connected) print $1
                next
              }
              { print }
            ' "$identity_dir/connected" ${identitiesFile} > "$identity_dir/identities"
            if ! grep -q '^[^#[:space:]]' "$identity_dir/identities"; then
              echo "passage: no configured identity is available; connect a configured YubiKey" >&2
              exit 1
            fi
            for i in "''${!args[@]}"; do
              if [[ "''${args[i]}" == ${identitiesFile} ]]; then
                args[i]="$identity_dir/identities"
              fi
            done
            ${pkgs.age}/bin/age "''${args[@]}"
            exit $?
          fi
        ''
      }
      exec ${pkgs.age}/bin/age "''${args[@]}"
    '';
  };

  recipientsFile =
    let
      recipients = map (identity: identity.recipient) identities ++ cfg.extraRecipients;
    in
    if recipients == [ ] then
      throw "secrets.nix: no recipients derived — configure public identities or extraRecipients"
    else
      pkgs.writeText "age-recipients" (lib.concatMapStrings (recipient: recipient + "\n") recipients);

  # The default wrapper puts the full git on PATH. Use the git of the profile.
  # The clipboard tools pull in perl through xdg-utils. Pipe to tcopy instead
  # of `passage show -c`.
  passage = pkgs.passage.override {
    git = pkgs.gitMinimal-runtime;
    wl-clipboard = null;
    xclip = null;
  };

  passageDispatch = pkgs.writeShellApplication {
    name = "passage";
    runtimeInputs = [
      pkgs.age
      pkgs.gitMinimal-runtime
      pkgs.coreutils
    ]
    # On Darwin, passage encodes with `openssl base64`.
    ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.openssl
    ++ cfg.plugins;
    text = ''
      export PASSAGE_DIR=${cfg.store}
      export PASSAGE_IDENTITIES_FILE=${identitiesFile}
      export PASSAGE_AGE=${passageAge}/bin/passage-age

      passage_bin=${passage}/bin/passage

      # add/insert: encrypt stdin (or a silent prompt) to a new *.age file,
      # written under the git toplevel so it lands in the flake source.
      secure_add() {
        local dir=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -d | --dir)
              if [ "$#" -lt 2 ]; then
                echo "passage: --dir requires an argument" >&2
                return 1
              fi
              dir="$2"
              shift 2
              ;;
            --dir=*)
              dir="''${1#--dir=}"
              shift
              ;;
            --)
              shift
              break
              ;;
            -*)
              echo "passage: unknown flag '$1'" >&2
              return 1
              ;;
            *) break ;;
          esac
        done

        if [ "$#" -ne 1 ]; then
          echo "Usage: passage add [--dir <writable-store>] <name>" >&2
          return 1
        fi
        local name="$1"

        case "$name" in
          /* | *..*)
            echo "passage: invalid name '$name'" >&2
            return 1
            ;;
        esac

        if [ -z "$dir" ]; then
          local root
          if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
            echo "passage: not in a git repo (run from inside the flake, or pass --dir <path>)" >&2
            return 1
          fi
          dir="$root/${cfg.writableStoreRelative}"
        fi

        if ! mkdir -p "$dir"; then
          echo "passage: cannot create $dir" >&2
          return 1
        fi
        if [ ! -w "$dir" ]; then
          echo "passage: $dir is not writable" >&2
          return 1
        fi

        local target="$dir/$name.age"
        if [ -e "$target" ]; then
          echo "passage: already exists: $target" >&2
          return 1
        fi
        mkdir -p "$(dirname "$target")"

        if [ -t 0 ]; then
          local value
          read -rsp "Value for $name: " value
          echo
          if [ -z "$value" ]; then
            echo "passage: empty value rejected" >&2
            return 1
          fi
          # printf is a bash builtin → $value never reaches a process argv
          if ! printf '%s' "$value" | age -R ${recipientsFile} -o "$target"; then
            rm -f "$target"
            return 1
          fi
        else
          if ! age -R ${recipientsFile} -o "$target"; then
            rm -f "$target"
            return 1
          fi
        fi

        echo "wrote $target"
        echo "next: git add, commit, rebuild"
      }

      case "''${1:-}" in
        add | insert)
          shift
          secure_add "$@"
          ;;
        edit)
          echo "passage: edit not supported (store is read-only)." >&2
          echo "  To rotate: delete the *.age file in your flake, then 'passage add <name>'." >&2
          exit 1
          ;;
        *) exec "$passage_bin" "$@" ;;
      esac
    '';
  };

  # Keep passage's shipped completions/man; override only the entrypoint.
  passageWrapped = pkgs.symlinkJoin {
    name = "passage-wrapped";
    paths = [ passage ];
    postBuild = ''
      rm -f "$out/bin/passage"
      ln -s ${passageDispatch}/bin/passage "$out/bin/passage"
    '';
  };

  ghToken = pkgs.callPackage ../../packages/gh-token {
    inherit identitiesFile recipientsFile;
    ageCommand = "${passageAge}/bin/passage-age";
  };
in
{
  options.programs.aldur.secrets = {
    enable = lib.mkEnableOption "passage-backed secret store";

    identities = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      description = ''
        Age identity files. Each is scanned for its `age1...` recipient to
        build the recipients file used by `passage add`, and all are
        combined for decryption. Only YubiKey identities on connected
        keys are used for decryption. Encryption uses all recipients.
        Identity stubs from `age-plugin-yubikey`
        are public info and safe in the nix store; do not put plaintext
        age secret keys here. Evaluation rejects plaintext secret keys and
        identities without an `age1...` recipient before generating store
        files. Files inside a flake source are copied into the store before
        this validation, so keep plaintext keys outside your flake entirely.
      '';
      example = lib.literalExpression "[ ./secrets/yubikey-a ./secrets/yubikey-b ]";
    };

    extraRecipients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional age recipient strings appended to the auto-derived
        list (e.g., a colleague's public key, or a software backup key
        whose identity you don't carry on this host).
      '';
      example = lib.literalExpression ''[ "age1xyz..." ]'';
    };

    store = lib.mkOption {
      type = lib.types.path;
      description = ''
        Directory of `*.age` files. Exposed as passage's read-only store
        via `$PASSAGE_DIR`.
      '';
      example = lib.literalExpression "./secrets/store";
    };

    writableStoreRelative = lib.mkOption {
      type = lib.types.str;
      default = "secrets";
      description = ''
        Path relative to the git toplevel where `passage add` writes new
        `*.age` files. Should match the on-disk location whose contents
        end up in `store` after the next rebuild. Override if your flake
        layout uses a subdir (e.g., `"secrets/store"`).
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ pkgs.age-plugin-yubikey ];
      defaultText = lib.literalExpression "[ pkgs.age-plugin-yubikey ]";
      description = ''
        Age plugin packages put on PATH alongside passage. Each backend
        referenced by `identities` or `extraRecipients` needs its plugin
        available for age to encrypt to / decrypt with that backend.
      '';
      example = lib.literalExpression "[ pkgs.age-plugin-yubikey pkgs.age-plugin-se ]";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.fish.functions.ghs = import ./fish/ghs.nix { inherit ghToken; };
    home.packages = [
      passageWrapped
      ghToken
      pkgs.gh
    ]
    ++ cfg.plugins;
  };
}
