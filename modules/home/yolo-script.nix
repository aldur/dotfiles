# Build an `<agent>-yolo` script: the agent without permission prompts, in
# the agent sandbox when it is enabled. Wrapper flags come first; everything
# after them goes to the agent. `--no-sandbox` runs the agent on the host
# for one launch, with a warning.
#
# `text` runs after the argument parsing. It launches the agent with the
# `sandbox` array in front: `exec "''${sandbox[@]}" codex "$@"`. The array
# is empty on the host. Each wrapper flag is available as `argc_<flag>`.
{
  pkgs,
  lib,
  config,
}:
{
  agent,
  describe,
  sandbox,
  flags ? { },
  runtimeInputs ? [ ],
  text,
}:
let
  sandboxed = sandbox && pkgs.stdenv.hostPlatform.isLinux;
  allFlags = flags // {
    no-sandbox = "Run on the host, outside the agent sandbox";
  };
  names = lib.attrNames allFlags;
  variables = map (name: "argc_" + lib.replaceStrings [ "-" ] [ "_" ] name) names;
in
pkgs.writeArgcApplication {
  name = "${agent}-yolo";
  inherit runtimeInputs;
  text = ''
    # @describe ${describe}
    ${lib.concatMapStringsSep "\n" (name: "# @flag --${name} ${allFlags.${name}}") names}
    # @arg args~ Arguments for ${agent}
    declare ${lib.concatStringsSep " " variables}
    argc_args=()
    # Only the wrapper flags at the front are for argc. The scan inserts
    # the `--` itself, so agent arguments need no separator.
    wrapper_args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        ${lib.concatMapStringsSep " | " (name: "--${name}") names} | -h | --help) wrapper_args+=("$1") ;;
        --) shift; break ;;
        *) break ;;
      esac
      shift
    done
    eval "$(argc --argc-eval "$0" "''${wrapper_args[@]}" -- "$@")"
    set -- "''${argc_args[@]}"

    sandbox=()
    if [ "''${argc_no_sandbox:-0}" -eq 1 ]; then
      echo "${agent}-yolo: ${
        if sandboxed then
          "WARNING: running on the host, outside the sandbox"
        else
          "there is no agent sandbox on this host"
      }" >&2
    ${lib.optionalString sandboxed ''
      else
        sandbox=(${lib.getExe config.programs.agent-sandbox.package} --profile ${agent} --)
    ''}fi
    ${text}
  '';
}
