{
  pkgs,
  lib,
  config,
  ...
}:
# age-based password store via passage (https://github.com/FiloSottile/passage),
# with identities and secrets baked into the Nix store.
let
  cfg = config.programs.aldur.secrets;

  # Concatenate the identities passage reads, but first refuse to bake a
  # plaintext age secret key into the world-readable nix store. age-plugin-*
  # identity stubs are public and fine; an age-keygen secret (AGE-SECRET-KEY-1
  # ...) is a decryption key and must never land here. This turns the option
  # doc's "do not put secret keys here" from a hope into a build failure.
  identitiesFile =
    pkgs.runCommand "age-identities" { inherit (cfg) identities; } ''
      for f in $identities; do
        if grep -q 'AGE-SECRET-KEY-1' "$f"; then
          echo "secrets.nix: refusing to store a plaintext age secret key from identity: $f" >&2
          echo "  identities must be public key material (e.g. age-plugin-yubikey stubs)." >&2
          exit 1
        fi
        cat "$f"
        echo
      done > $out
    '';

  recipientsFile =
    pkgs.runCommand "age-recipients"
      {
        inherit (cfg) identities;
        extras = builtins.toFile "extra-age-recipients" (
          lib.concatMapStrings (r: r + "\n") cfg.extraRecipients
        );
      }
      ''
        {
          for f in $identities; do
            # Per-file so one identity without a recipient fails loudly
            # instead of being masked by another file's recipient (the old
            # `grep | head` swallowed grep's exit status).
            rec=$(grep -oE 'age1[a-z0-9]+' "$f" | head -1)
            if [ -z "$rec" ]; then
              echo "secrets.nix: no 'age1...' recipient found in identity: $f" >&2
              exit 1
            fi
            printf '%s\n' "$rec"
          done
          cat "$extras"
        } > $out

        if ! [ -s "$out" ]; then
          echo "no recipients derived — check your identity files contain 'age1...' lines" >&2
          exit 1
        fi
      '';

  passageDispatch = pkgs.writeShellApplication {
    name = "passage";
    runtimeInputs = [
      pkgs.age
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      export PASSAGE_DIR=${cfg.store}
      export PASSAGE_IDENTITIES_FILE=${identitiesFile}

      passage_bin=${pkgs.passage}/bin/passage

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
    paths = [ pkgs.passage ];
    postBuild = ''
      rm -f "$out/bin/passage"
      ln -s ${passageDispatch}/bin/passage "$out/bin/passage"
    '';
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
        concatenated into the file passage reads via
        $PASSAGE_IDENTITIES_FILE. Identity stubs from `age-plugin-yubikey`
        are public info and safe in the nix store; do not put plaintext
        age secret keys here — the build fails if an identity contains an
        `AGE-SECRET-KEY-1...` line, and if any identity has no `age1...`
        recipient.
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
    home.packages = [ passageWrapped ] ++ cfg.plugins;
  };
}
