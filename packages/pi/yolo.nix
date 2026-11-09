{ pkgs, pi }:
let
  inherit (pkgs) lib;
  sandbox = import ../../modules/home/agent-sandbox/package.nix { inherit pkgs lib; } {
    profiles.pi.extraEnvironmentAllowlist = [
      "LLAMA_BASE_URL"
      "PI_OPENAI_BASE_URL"
      "PI_OPENAI_API_KEY"
      "PI_OPENAI_PROFILE"
      "PI_SUBAGENT_CONCURRENCY"
      "PI_SUBAGENT_MAX_TASKS"
    ];
  };
in
import ../../modules/home/yolo-script.nix {
  inherit pkgs lib;
  config.programs.agent-sandbox.package = sandbox;
} {
  agent = "pi";
  describe = "Run Pi in the agent sandbox";
  sandbox = true;
  text = ''
    if [ "''${#sandbox[@]}" -gt 0 ]; then
      agent_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
      mkdir -p "$agent_dir"
      sandbox=("''${sandbox[@]:0:''${#sandbox[@]}-1}" --rw "$agent_dir" --env PI_CODING_AGENT_DIR --)
    fi
    exec "''${sandbox[@]}" ${lib.getExe pi} "$@"
  '';
}
