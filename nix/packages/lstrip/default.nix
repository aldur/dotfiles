{
  writeShellApplication,
  gnused,
}:

writeShellApplication {
  name = "lstrip";

  runtimeInputs = [ gnused ];

  text = ''
    case "''${1:-}" in
        -h|--help)
            cat <<'EOF'
    Usage: lstrip [-h|--help]

    Strip leading whitespace from each line of stdin.

    Options:
      -h, --help    Show this help and exit
    EOF
            exit 0
            ;;
    esac

    sed 's/^[[:space:]]*//'
  '';
}
