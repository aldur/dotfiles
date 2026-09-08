# Install one command for all agents and for arbitrary development tools.
{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  agents = osConfig.programs.aldur;
  profile = cfg: {
    runtimeAllowlist = cfg.extraRuntimeDirAllowlist;
    inherit (cfg) extraDbusTalk allowNixDaemon extraEnvironmentAllowlist;
    inherit (cfg.filesystem) readOnlyPaths readWritePaths;
  };

  package = import ./package.nix { inherit pkgs lib; } {
    profiles =
      lib.optionalAttrs agents.codex.enable {
        codex = profile agents.codex.sandbox // {
          stateKind = "codex";
          agentReadOnlyPaths = [ "~/.codex/packages" ];
        };
      }
      // lib.optionalAttrs agents.claude-code.enable {
        claude = profile agents.claude-code.sandbox // {
          stateKind = "claude";
          agentReadOnlyPaths = [ "~/.local/share/claude/versions" ];
          extraEnvironmentAllowlist = agents.claude-code.sandbox.extraEnvironmentAllowlist ++ [
            "IS_SANDBOX"
            "CLAUBBIT"
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
            "DISABLE_AUTOUPDATER"
          ];
        };
      };
  };
in
{
  options.programs.agent-sandbox.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    default = package;
    description = "Shared sandbox command, including the enabled agents' mount profiles.";
  };

  config.home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    config.programs.agent-sandbox.package
  ];
}
