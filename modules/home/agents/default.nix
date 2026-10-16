{
  config,
  lib,
  ...
}:
let
  instructions = { source = ./AGENTS.md; };
in
{
  home.file =
    lib.optionalAttrs config.programs.aldur.codex.enable {
      ".codex/AGENTS.md" = instructions;
    }
    // lib.optionalAttrs config.programs.aldur.claude-code.enable {
      "${config.programs.claude-code.configDir}/CLAUDE.md" = instructions;
    }
    // lib.optionalAttrs config.programs.pi.enable {
      ".pi/agent/AGENTS.md" = instructions;
    };
}
