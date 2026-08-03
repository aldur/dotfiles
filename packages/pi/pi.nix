{
  lib,
  stdenv,
  runCommand,
  writeShellApplication,
  nodejs,
  pnpm,
  pi-coding-agent,
  # Plugin derivations to bundle, keyed by name (see ./plugins). Each is
  # auto-loaded on every run through `pi -e <plugin>/index.ts` (a
  # position-independent repeatable flag; a plugin with a different entry
  # point can set `passthru.entryPoint`) — no `pi install` (which git-clones
  # over the network into a mutable ~/.pi and edits pi settings), no flags to
  # remember. Same spirit as llmWithPlugins.
  plugins ? { },
}:

let
  pluginFlags = lib.concatMapStringsSep " " (
    plugin: "-e ${lib.escapeShellArg (plugin.entryPoint or "${plugin}/index.ts")}"
  ) (lib.attrValues plugins);

  npmPackage = "@earendil-works/pi-coding-agent";

  # pnpm rather than npm: it does not run dependency lifecycle scripts by
  # default and installs through a content-addressed store, so a compromised
  # release has less to work with. pi detects a pnpm install on its own (the
  # `.pnpm/` in the package path) and self-updates with pnpm from then on.
  #
  # pnpm's own default global directory, so a pnpm run outside this wrapper
  # sees the same install; an exported PNPM_HOME still wins.
  defaultPnpmHome =
    if stdenv.hostPlatform.isDarwin then
      "$HOME/Library/pnpm"
    else
      "\${XDG_DATA_HOME:-$HOME/.local/share}/pnpm";

  # Same spirit as the codex wrapper (modules/home/codex.nix): the Nix build
  # is a bootstrap, and once a self-managed release exists it takes over.
  wrapper = writeShellApplication {
    name = "pi";
    text = ''
      # The anonymous install/update ping (enableInstallTelemetry) defaults to
      # on; PI_TELEMETRY=0 turns it off, along with provider attribution
      # headers (docs/usage.md). Analytics (enableAnalytics) is already opt-in.
      # Assigned as a default so the runtime override stays available.
      export PI_TELEMETRY="''${PI_TELEMETRY-0}"

      # pi only recognises its package subcommands as the first argument, and
      # rejects `-e` after them, so those run without the plugin flags.
      flags=(${pluginFlags})
      skip_version_check=1
      case "''${1-}" in
      install | remove | uninstall | update | list | config)
        flags=()
        skip_version_check=
        ;;
      esac

      # pi never installs an update on its own, but every start pings
      # pi.dev/api/latest-version and nags about newer releases. Turned off, so
      # updates only ever happen when `pi update` is run — which resolves the
      # release to install through that same check, hence the exception above.
      export PI_SKIP_VERSION_CHECK="''${PI_SKIP_VERSION_CHECK-$skip_version_check}"

      pnpm_home="''${PNPM_HOME:-${defaultPnpmHome}}"

      # node and pnpm are put on PATH only for the self-managed copy — it runs
      # through a `#!/usr/bin/env node` shim and shells out to pnpm to update
      # itself, and pnpm refuses to install globally unless its global bin
      # directory is on PATH. The Nix build has its interpreter baked in, so
      # the fallback below keeps a clean environment.
      use_pnpm() {
        export PNPM_HOME="$pnpm_home"
        export PATH="$pnpm_home/bin:$pnpm_home:${
          lib.makeBinPath [
            nodejs
            pnpm
          ]
        }:$PATH"
      }

      # Prefer a pi that has updated itself. Checking the install path directly
      # (rather than PATH) makes the updated copy win even when pnpm's global
      # bin directory is not on PATH. pnpm 11 links binaries into
      # $PNPM_HOME/bin, earlier versions into $PNPM_HOME itself.
      for user_pi in "$pnpm_home/bin/pi" "$pnpm_home/pi"; do
        if [ -x "$user_pi" ]; then
          use_pnpm
          exec "$user_pi" "''${flags[@]}" "$@"
        fi
      done

      # No self-managed copy yet: `pi update` on the store binary can only
      # report that it cannot update itself, so run the install it would have
      # run. From here on the loop above takes over and pi updates itself.
      if [ "''${1-}" = update ]; then
        use_pnpm
        exec pnpm install -g \
          --ignore-scripts --config.minimumReleaseAge=0 ${npmPackage}
      fi

      exec ${lib.getExe pi-coding-agent} "''${flags[@]}" "$@"
    '';
  };
in

# Wrapped in a derivation of its own only to keep the versioned name (a
# writeShellApplication is named after its binary).
runCommand "pi-with-plugins-${pi-coding-agent.version}"
  {
    # Plugins stay reachable (e.g. `pi.plugins.pi-llama`) so nix-update can
    # bump their pins in CI without dedicated flake outputs.
    passthru = { inherit plugins; };
    meta = pi-coding-agent.meta // {
      mainProgram = "pi";
      description = "pi-coding-agent bundled with plugins";
    };
  }
  ''
    mkdir -p $out/bin
    ln -s ${lib.getExe wrapper} $out/bin/pi
  ''
