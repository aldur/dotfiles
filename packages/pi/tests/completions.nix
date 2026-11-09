{
  pkgs,
  pi,
  pi-yolo,
}:
pkgs.runCommand "pi-completions-test"
  {
    nativeBuildInputs = [
      pkgs.fish
      pkgs.python3
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$TMPDIR/bin"
    cat > "$TMPDIR/bin/pi" <<'SH'
    #!${pkgs.runtimeShell}
    test "$*" = --list-models || exit 1
    cat <<'MODELS'
    provider  model          context  max-out  thinking  images
    alpha     model-one      200K     32K      yes       yes
    beta      org/model-two  128K     16K      no        no
    MODELS
    SH
    chmod +x "$TMPDIR/bin/pi"
    export PATH="$TMPDIR/bin:${pi-yolo}/bin:$PATH"
    python3 - <<'PY'
    import subprocess

    def complete(line):
        script = """
    set fish_complete_path ${pi}/share/fish/vendor_completions.d ${pi-yolo}/share/fish/vendor_completions.d $fish_complete_path
    complete -C $argv[1]
    """
        result = subprocess.run(["fish", "--no-config", "-c", script, "--", line],
                                check=True, capture_output=True, text=True)
        return {row.split("\t")[0] for row in result.stdout.splitlines()}

    levels = {"off", "minimal", "low", "medium", "high", "xhigh", "max"}
    for command in ("pi", "pi-yolo"):
        assert complete(command + " --thinking ") == levels
        assert complete(command + " --thinking=x") == {"--thinking=xhigh"}
        assert {"--model", "--models"} <= complete(command + " --mod")
        assert complete(command + " --model ") == {"alpha/model-one", "beta/org/model-two"}
        assert complete(command + " --provider ") == {"alpha", "beta"}
        assert complete(command + " --provider alpha --model ") == {"model-one"}
        assert complete(command + " --provider=beta --model ") == {"org/model-two"}
        assert complete(command + " --mode ") == {"text", "json", "rpc"}
    assert "--network" in complete("pi-yolo --net")
    assert complete("pi-yolo --network host --thinking ") == levels
    assert complete("pi-yolo --no-sandbox --model ") == {"alpha/model-one", "beta/org/model-two"}
    PY
    touch "$out"
  ''
