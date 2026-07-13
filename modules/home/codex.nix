{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  osConfig,
  ...
}:
let
  enabled = osConfig.programs.aldur.codex.enable;

  # Prefer Codex's standalone release after `codex update`. The standalone
  # installer keeps its current release under ~/.codex; checking it directly
  # makes the downloaded version win even when ~/.local/bin is not on PATH.
  codex = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      standalone_root="$HOME/.codex/packages/standalone/current"
      for standalone in "$standalone_root/bin/codex" "$standalone_root/codex"; do
        if [ -x "$standalone" ]; then
          exec "$standalone" "$@"
        fi
      done

      # The Nix binary is not a self-managed installation, so its native
      # `codex update` cannot select an update method. Bootstrap the official
      # standalone installer here; later updates are handled by that release.
      if [ "$#" -gt 0 ] && [ "$1" = "update" ]; then
        curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 /bin/sh
        exit $?
      fi

      exec ${lib.getExe pkgsUnstable.codex} "$@"
    '';
  };
in
{
  # Package installation and config.toml generation are provided by Home
  # Manager's upstream programs.codex module. Setting its package to null lets
  # this wrapper occupy the command name while the upstream module keeps
  # managing the configuration.
  config = lib.mkIf enabled {
    programs.codex = {
      enable = true;
      package = null;
      settings = {
        analytics.enabled = false;
        feedback.enabled = false;
        otel = {
          exporter = "none";
          metrics_exporter = "none";
          trace_exporter = "none";
        };

        tui = {
          status_line = [
            "current-dir"
            "git-branch"
            "project-name"
            "context-used"
            "used-tokens"
            "model-with-reasoning"
            "context-window-size"
          ];
          status_line_use_colors = true;
        };
      };
    };

    home = {
      packages = [ codex ];
      shellAliases.codex-yolo = "codex --dangerously-bypass-approvals-and-sandbox";
    };
  };
}
