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
  sandboxCfg = osConfig.programs.aldur.codex.sandbox;
  sandbox = sandboxCfg.enable && pkgs.stdenv.hostPlatform.isLinux;
  tomlFormat = pkgs.formats.toml { };
  tomlPython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);

  codexSettings = {
    # The model catalog sets the summary to "none" for gpt-6-astra. Without a
    # summary, a session records only the encrypted reasoning, and agent-log
    # cannot show a thinking turn.
    model_reasoning_summary = "auto";
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
  codexSettingsFile = tomlFormat.generate "codex-config" codexSettings;

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

  # `codex-yolo` runs codex with its native sandbox and approvals off, in
  # the agent sandbox when it is enabled. The outer wrapper supplies the
  # filesystem allowlist and filters session sockets for the entire agent
  # process.
  codex-yolo = pkgs.writeArgcApplication {
    name = "codex-yolo";
    text = ''
      # @describe Run codex in the sandbox, with no approvals and no native sandbox
      # @arg args~ Arguments for codex
      exec ${lib.optionalString sandbox "${lib.getExe config.programs.agent-sandbox.package} --profile codex -- "}codex --dangerously-bypass-approvals-and-sandbox "$@"
    '';
  };
in
{
  # Keep config.toml writable: Codex stores runtime state such as project trust
  # in the same file. The activation below recursively merges these declarative
  # defaults into that state, with the Nix-managed values winning conflicts.
  config = lib.mkIf enabled {
    programs.codex = {
      enable = true;
      package = null;
    };

    home = {
      activation.codexSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.codex/config.toml"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge Codex settings from ${codexSettingsFile} into $target"
        else
          mkdir -p "$(dirname "$target")"
          ${lib.getExe tomlPython} ${./merge-codex-config.py} \
            ${codexSettingsFile} "$target"
        fi
      '';

      packages = [
        codex
        codex-yolo
      ];
    };
  };
}
