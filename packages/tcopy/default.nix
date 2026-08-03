{
  writeShellApplication,
  coreutils,
}:

writeShellApplication {
  name = "tcopy";

  runtimeInputs = [ coreutils ];

  text = ''
    case "''${1:-}" in
        -h|--help)
            cat <<'EOF'
    Usage: tcopy [--] [TEXT...]

    Copy TEXT (or stdin, when no arguments are given) to the system clipboard
    with an OSC 52 escape sequence, which works over SSH and through tmux
    (`set-clipboard on` forwards the sequence to the outer terminal).

    The sequence is written to the controlling terminal rather than stdout, so
    it still reaches the terminal when a caller captures stdout — which is how
    lazygit and friends run `os.copyToClipboardCmd`.

    Options:
      -h, --help    Show this help and exit
    EOF
            exit 0
            ;;
        --) shift ;;
    esac

    if [ "$#" -gt 0 ]; then
        data="$*"
    else
        data=$(cat)
    fi

    # `base64 | tr -d '\n'` not `base64 -w 0`: -w is GNU-only and macOS
    # /usr/bin/base64 rejects it. tr gives single-line output on both.
    encoded=$(printf '%s' "$data" | base64 | tr -d '\n')

    # Terminals cap how long an OSC string they will buffer (tmux included), and
    # silently drop anything past it — say so rather than appearing to succeed.
    if [ "''${#encoded}" -gt 100000 ]; then
        echo "tcopy: payload is ''${#encoded} bytes encoded; the terminal will likely truncate it" >&2
    fi

    osc52() { printf '\033]52;c;%s\007' "$1"; }

    # Try the controlling terminal, fall back to stdout. Testing `[ -w /dev/tty ]`
    # first would not work: the device node exists and is writable even when the
    # process has no controlling terminal, where the open fails with ENXIO — so
    # attempt the write and let it fail.
    if ! { osc52 "$encoded" > /dev/tty; } 2>/dev/null; then
        osc52 "$encoded"
    fi
  '';
}
