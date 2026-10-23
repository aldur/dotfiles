# Install one command for all agents and for arbitrary development tools.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  agents = config.programs.aldur;
  instructionsDirectory =
    let
      directory = config.programs.agent-instructions.directory;
      homePrefix = "${config.home.homeDirectory}/";
    in
    if lib.hasPrefix homePrefix directory then
      "~/${lib.removePrefix homePrefix directory}"
    else
      directory;
  profile = cfg: {
    runtimeAllowlist = cfg.extraRuntimeDirAllowlist;
    inherit (cfg)
      extraDbusTalk
      allowNixDaemon
      allowDocker
      network
      extraEnvironmentAllowlist
      ;
    inherit (cfg.filesystem) readOnlyPaths readWritePaths;
  };

  package = import ./package.nix { inherit pkgs lib; } {
    profiles =
      lib.optionalAttrs agents.codex.enable {
        codex = profile agents.codex.sandbox // {
          stateKind = "codex";
          agentReadOnlyPaths = [
            "~/.codex/packages"
            "~/.agents/skills"
            instructionsDirectory
          ];
        };
      }
      // lib.optionalAttrs agents.claude-code.enable {
        claude = profile agents.claude-code.sandbox // {
          stateKind = "claude";
          agentReadOnlyPaths = [
            "~/.local/share/claude/versions"
            instructionsDirectory
          ];
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
