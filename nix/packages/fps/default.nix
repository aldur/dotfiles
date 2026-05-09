{
  writeShellApplication,
  fzf,
  procps,
}:

writeShellApplication {
  name = "fps";

  runtimeInputs = [
    fzf
    procps
  ];

  text = ''
    case "''${1:-}" in
        -h|--help)
            cat <<'EOF'
    Usage: fps [-h|--help]

    Interactive process picker. Wraps `ps` with `fzf`.

    Keybindings:
      <ctrl-k>  kill the highlighted process (SIGKILL)
      <enter>   print the highlighted process's PID and exit

    Options:
      -h, --help    Show this help and exit
    EOF
            exit 0
            ;;
    esac

    ps -eo pid,user,%cpu,%mem,args \
      | fzf --header-lines=1 \
            --footer "<c-k> kills PID; <cr> prints PID" \
            --bind 'ctrl-k:execute(kill -KILL {1})+abort,enter:become(echo {1})'
  '';
}
