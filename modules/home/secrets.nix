{
  pkgs,
  lib,
  config,
  ...
}:
# age-based password store via passage (https://github.com/FiloSottile/passage).
#
# Three Nix paths get imported into the nix store on rebuild:
#   - `identities`: list of age identity files (yubikey stubs etc.) — concatenated
#     into a single file pointed at by $PASSAGE_IDENTITIES_FILE.
#   - `store`: directory of *.age files — exposed as passage's read-only store
#     via $PASSAGE_DIR.
# Recipients are auto-derived from each identity's `# Recipient: age1...` line.
# Add more via `extraRecipients` for keys you don't have identities for.
#
# All user-facing operations go through one command: `secret`. Reads pass
# through to passage; `secret add` is a secure encryptor that writes to
# `<git toplevel>/${writableStoreRelative}` (or `--dir <path>`).
let
  cfg = config.programs.aldur.secrets;

  identitiesFile = pkgs.concatTextFile {
    name = "age-identities";
    files = cfg.identities;
  };

  recipientsFile = pkgs.runCommand "age-recipients" {
    identities = cfg.identities;
    extras = builtins.toFile "extra-age-recipients" (
      lib.concatMapStrings (r: r + "\n") cfg.extraRecipients
    );
  } ''
    {
      for f in $identities; do
        grep -oE 'age1[a-z0-9]+' "$f" | head -1
      done
      cat "$extras"
    } > $out

    if ! [ -s "$out" ]; then
      echo "no recipients derived — check your identity files contain 'age1...' lines" >&2
      exit 1
    fi
  '';
in
{
  options.programs.aldur.secrets = {
    enable = lib.mkEnableOption "passage-backed secret store";

    identities = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      description = ''
        Age identity files. Each is scanned for its `age1...` recipient to
        build the recipients file used by `secret add`, and all are
        concatenated into the file passage reads via
        $PASSAGE_IDENTITIES_FILE. Identity stubs from `age-plugin-yubikey`
        are public info and safe in the nix store; do not put plaintext
        age secret keys here.
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
        Path relative to the git toplevel where `secret add` writes new
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
    home.packages = [ pkgs.passage ] ++ cfg.plugins;

    home.sessionVariables = {
      PASSAGE_DIR = "${cfg.store}";
      PASSAGE_IDENTITIES_FILE = "${identitiesFile}";
    };

    programs.fish.functions = {
      _secret-add = {
        description = "Internal: encrypt stdin (or a silent prompt) to a new *.age file";
        body = ''
          argparse 'd/dir=' -- $argv
          or return 1

          if test (count $argv) -ne 1
            echo "Usage: secret add [--dir <writable-store>] <name>" >&2
            return 1
          end
          set -l name $argv[1]

          if string match -q '/*' -- $name; or string match -q '*..*' -- $name
            echo "secret: invalid name '$name'" >&2
            return 1
          end

          set -l dir
          if set -q _flag_dir
            set dir $_flag_dir
          else
            set -l root (git rev-parse --show-toplevel 2>/dev/null)
            or begin
              echo "secret: not in a git repo (run from inside the flake, or pass --dir <path>)" >&2
              return 1
            end
            set dir "$root/${cfg.writableStoreRelative}"
          end

          mkdir -p "$dir"
          or begin
            echo "secret: cannot create $dir" >&2
            return 1
          end
          if not test -w "$dir"
            echo "secret: $dir is not writable" >&2
            return 1
          end

          set -l target "$dir/$name.age"
          if test -e "$target"
            echo "secret: already exists: $target" >&2
            return 1
          end

          mkdir -p (dirname "$target")
          or return 1

          if isatty stdin
            read -s -P "Value for $name: " value
            echo
            if test -z "$value"
              echo "secret: empty value rejected" >&2
              return 1
            end
            # echo is a fish builtin → $value never reaches argv (no /proc leak)
            if not echo -n -- $value | age -R ${recipientsFile} -o $target
              rm -f $target
              return 1
            end
          else
            if not age -R ${recipientsFile} -o $target
              rm -f $target
              return 1
            end
          end

          echo "wrote $target"
          echo "next: git add, commit, rebuild"
        '';
      };

      secret = {
        description = "Unified secrets command: passage wrapper with a secure `add` subcommand";
        body = ''
          # passage locates its store + identities via these; export them here
          # so the command works regardless of whether the session vars reached
          # this shell — a fish session predating the last switch, a non-login
          # shell, tmux panes, or scripts would otherwise miss them and passage
          # would fall back to its (nonexistent) ~/.passage defaults.
          set -lx PASSAGE_DIR ${cfg.store}
          set -lx PASSAGE_IDENTITIES_FILE ${identitiesFile}

          if test (count $argv) -eq 0
            command passage
            return
          end

          switch $argv[1]
            case add insert
              _secret-add $argv[2..]
            case edit
              echo "secret: edit not supported (store is read-only)." >&2
              echo "  To rotate: delete the *.age file in your flake, then 'secret add <name>'." >&2
              return 1
            case '*'
              command passage $argv
          end
        '';
      };
    };
  };
}
