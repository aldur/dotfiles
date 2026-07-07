{
  lib,
  runCommand,
  makeWrapper,
  pi-coding-agent,
  # Plugin derivations to bundle, keyed by name (see ./plugins). Each is
  # auto-loaded on every run through `pi -e <plugin>/index.ts` (a
  # position-independent repeatable flag; a plugin with a different entry
  # point can set `passthru.entryPoint`) — no `pi install` (which git-clones
  # over the network into a mutable ~/.pi and edits pi settings), no flags to
  # remember. Same spirit as llmWithPlugins.
  plugins ? { },
}:

runCommand "pi-with-plugins-${pi-coding-agent.version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    # Plugins stay reachable (e.g. `pi.plugins.pi-llama`) so nix-update can
    # bump their pins in CI without dedicated flake outputs.
    passthru = { inherit plugins; };
    meta = pi-coding-agent.meta // {
      mainProgram = "pi";
      description = "pi-coding-agent bundled with plugins";
    };
  }
  ''
    # The anonymous install/update ping (enableInstallTelemetry) defaults to
    # on; PI_TELEMETRY=0 turns it off, along with provider attribution
    # headers (docs/usage.md). Analytics (enableAnalytics) is already opt-in.
    # --set-default keeps the runtime override available.
    makeWrapper ${lib.getExe pi-coding-agent} $out/bin/pi \
      --set-default PI_TELEMETRY 0 \
      ${
        lib.concatMapStringsSep " " (plugin: ''--add-flags "-e ${plugin.entryPoint or "${plugin}/index.ts"}"'') (
          lib.attrValues plugins
        )
      }
  ''
