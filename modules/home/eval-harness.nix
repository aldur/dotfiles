# Build an eval harness: an agent and the files of a fresh $HOME, as the
# activation of its module would write them.
#
# Output:
#   bin/eval-harness <model> <prompt> [effort=<level>]
#     Runs the agent once in the current directory. JSON events on stdout.
#   home/          Files for the fresh $HOME of a run.
#   harness.json   Name, version, `params` (name -> allowed values), and
#                  paths relative to $HOME: `credentials` to copy from the
#                  host, `sessionDirs` to keep after the run.
#   usage.jq       jq filter: the array of JSON events -> token usage, with
#                  the fields below. null if the harness does not report one.
#   progress.jq    jq filter: one JSON event -> zero or more short lines, such
#                  as the tool calls and the messages of the agent.
{ pkgs, lib }:
{
  name,
  version,
  # Path relative to $HOME -> file or directory to copy there. A target
  # inside another target is copied after it.
  home,
  credentials,
  sessionDirs,
  # Bash that runs the agent, with $model, $prompt, and $effort (can be empty).
  command,
  # The values that the agent accepts for effort=<level>.
  effortLevels,
  # jq filter for usage.jq. Output: input_tokens (not from the cache),
  # cache_read_tokens, cache_write_tokens, output_tokens, reasoning_tokens
  # (part of output_tokens), cost_usd (as the harness calculates it), and
  # models (the model IDs that the provider reports).
  usage,
  # jq filter for progress.jq: one event -> zero or more strings.
  progress,
}:
let
  bin = pkgs.writeShellApplication {
    name = "eval-harness";
    text = ''
      if [ $# -lt 2 ]; then
        echo "usage: eval-harness <model> <prompt> [effort=<level>]" >&2
        exit 2
      fi
      model=$1 prompt=$2
      shift 2
      effort=""
      for param in "$@"; do
        case $param in
          ${
            lib.concatMapStringsSep " | " (level: "effort=${level}") effortLevels
          }) effort=''${param#effort=} ;;
          *)
            echo "eval-harness: unknown parameter: $param" >&2
            exit 2
            ;;
        esac
      done
      ${command}
    '';
  };
  metadata = pkgs.writeText "harness.json" (
    builtins.toJSON {
      params.effort = effortLevels;
      inherit
        name
        version
        credentials
        sessionDirs
        ;
    }
  );
in
pkgs.runCommand "eval-harness-${name}" { } ''
  mkdir -p "$out/bin" "$out/home"
  ln -s ${lib.getExe bin} "$out/bin/eval-harness"
  cp ${metadata} "$out/harness.json"
  cp ${pkgs.writeText "usage.jq" usage} "$out/usage.jq"
  # Progress is only for display: an unknown event gives no line, not an
  # error. Each line is one line of at most 200 characters.
  cp ${pkgs.writeText "progress.jq" ''
    (try (${progress}) catch empty) | strings | gsub("\\s+"; " ") | .[0:200]
  ''} "$out/progress.jq"
  echo '{}' | ${lib.getExe pkgs.jq} -r -f "$out/progress.jq" >/dev/null
  # The filter must give all the fields, also for a run with no events.
  ${lib.getExe pkgs.jq} -e -s -f "$out/usage.jq" </dev/null \
    | ${lib.getExe pkgs.jq} -e 'keys == ["cache_read_tokens", "cache_write_tokens", "cost_usd", "input_tokens", "models", "output_tokens", "reasoning_tokens"]'
  ${lib.concatStrings (
    lib.mapAttrsToList (target: source: ''
      mkdir -p "$(dirname "$out/home/${target}")"
      cp -rL --no-preserve=mode ${source} "$out/home/${target}"
    '') home
  )}
''
