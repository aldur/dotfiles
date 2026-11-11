{ pkgs, pi }:
let
  inherit (pkgs) lib;
  sandbox = import ../../modules/home/agent-sandbox/package.nix { inherit pkgs lib; } {
    profiles.pi.extraEnvironmentAllowlist = [
      "LLAMA_BASE_URL"
      "LLAMA_API_KEY"
      "PI_OPENAI_BASE_URL"
      "PI_OPENAI_API_KEY"
      "PI_OPENAI_PROFILE"
      "PI_SUBAGENT_CONCURRENCY"
      "PI_SUBAGENT_MAX_TASKS"
    ];
  };
  wrapper =
    import ../../modules/home/yolo-script.nix
      {
        inherit pkgs lib;
        config.programs.agent-sandbox.package = sandbox;
      }
      {
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
      };
in
wrapper.overrideAttrs (old: {
  buildCommand = old.buildCommand + ''
    cat >> $out/share/fish/vendor_completions.d/pi-yolo.fish <<'FISH'
    function __dotfiles_pi_yolo_wrapper
        set -l skip 0
        set -l words (commandline -opc)
        for word in $words[2..-1]
            if test $skip = 1
                set skip 0
                continue
            end
            switch $word
                case ${lib.concatMapStringsSep " " (name: "--${name}") wrapper.wrapperFlags}
                case ${lib.concatMapStringsSep " " (name: "--${name}") wrapper.wrapperOptions}
                    set skip 1
                case ${lib.concatMapStringsSep " " (name: "'--${name}=*'") wrapper.wrapperOptions}
                case '*'
                    return 1
            end
        end
        return 0
    end
    complete -c pi-yolo -e
    complete -c pi-yolo -w pi
    complete -c pi-yolo -x -n __dotfiles_pi_yolo_wrapper -a '(_argc_completer)'
    FISH
  '';
})
