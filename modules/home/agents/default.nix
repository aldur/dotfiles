{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled =
    config.programs.aldur.codex.enable
    || config.programs.aldur.claude-code.enable
    || config.programs.pi.enable;
  directory = "${config.xdg.configHome}/agents";
  homePrefix = "${config.home.homeDirectory}/";
  runtimeDirectory =
    if lib.hasPrefix homePrefix directory then
      ''"$HOME"/${lib.escapeShellArg (lib.removePrefix homePrefix directory)}''
    else
      lib.escapeShellArg directory;
  # SBOM tools cannot inspect a store output that is itself a dangling link.
  instructions = name: {
    source = pkgs.runCommand "agent-instructions-${name}" { } ''
      mkdir "$out"
      ln -s ${lib.escapeShellArg "${directory}/AGENTS.md"} "$out"/${lib.escapeShellArg name}
    '';
    recursive = true;
  };
  reset = pkgs.writeShellApplication {
    name = "reset-agent-instructions";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      directory=${runtimeDirectory}
      umask 077
      mkdir -p -- "$directory"
      temporary=$(mktemp "$directory/.AGENTS.md.XXXXXX")
      trap 'rm -f -- "$temporary"' EXIT
      install -m 600 ${./AGENTS.md} "$temporary"
      mv -fT -- "$temporary" "$directory/AGENTS.md"
    '';
  };
in
{
  options.programs.agent-instructions = {
    directory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = directory;
      description = "Directory containing the writable shared agent instructions.";
    };
    reset = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = reset;
      description = "Restore the shared agent instructions from dotfiles.";
    };
  };

  config.home = {
    file =
      lib.optionalAttrs config.programs.aldur.codex.enable {
        ".codex" = instructions "AGENTS.md";
      }
      // lib.optionalAttrs config.programs.aldur.claude-code.enable {
        "${config.programs.claude-code.configDir}" = instructions "CLAUDE.md";
      }
      // lib.optionalAttrs config.programs.pi.enable {
        ".pi/agent" = instructions "AGENTS.md";
      };

    activation.agentInstructions = lib.mkIf enabled (
      lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${lib.getExe config.programs.agent-instructions.reset}
      ''
    );
  };
}
