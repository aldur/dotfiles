{
  lib,
  stdenv,
  runCommand,
  writeShellApplication,
  writeShellScriptBin,
  nodejs,
  pnpm,
  pi-coding-agent,
  playwright-lazy ? null,
  tavily-cli,
  modelsCatalog,
  selfUpdates ? true,
  # Plugin derivations to bundle, keyed by name (see ./plugins). Each is
  # auto-loaded on every run through `pi -e <plugin>/index.ts` (a
  # position-independent repeatable flag; a plugin with a different entry
  # point can set `passthru.entryPoint`) — no `pi install` (which git-clones
  # over the network into a mutable ~/.pi and edits pi settings), no flags to
  # remember. Same spirit as llmWithPlugins.
  plugins ? { },
}:

let
  browserEnabled = playwright-lazy != null;
  pluginPaths = map (plugin: plugin.entryPoint or "${plugin}/index.ts") (lib.attrValues plugins);
  pluginFlags = lib.concatMapStringsSep " " (path: "-e ${lib.escapeShellArg path}") pluginPaths;

  helpSections =
    lib.optionalString (plugins ? pi-llama) ''
      llama.cpp provider:
        LLAMA_BASE_URL  Server API URL, including /v1.
                        Set this to enable the provider.

        Example:
          LLAMA_BASE_URL=http://my-server:8080/v1 pi

    ''
    + lib.optionalString (plugins ? pi-openai-discovery) ''
      OpenAI-compatible provider:
        PI_OPENAI_BASE_URL  Server API URL, including /v1.
        PI_OPENAI_API_KEY   API key, if required.
        PI_OPENAI_PROFILE   models.dev provider ID.

    ''
    + lib.optionalString browserEnabled ''
      Browser cache:
        pi browser-prefetch  Install pinned Chromium before an offline session.

    '';

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

  # Same spirit as the codex wrapper (modules/home/codex): the Nix build
  # is a bootstrap, and once a self-managed release exists it takes over.
  wrapper = writeShellApplication {
    name = "pi";
    runtimeInputs = lib.optional (tavily-cli != null) tavily-cli;
    text = ''
      if [ "''${1-}" = browser-prefetch ]; then
        ${lib.optionalString (!browserEnabled) ''
          echo 'Browser support is disabled in this Pi package.' >&2
          exit 1
        ''}
        ${lib.optionalString browserEnabled ''
          shift
          export PLAYWRIGHT_BROWSER_STATE_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/browser"
          exec ${playwright-lazy}/bin/playwright-browser-prefetch "$@"
        ''}
      fi

      # The anonymous install/update ping (enableInstallTelemetry) defaults to
      # on; PI_TELEMETRY=0 turns it off, along with provider attribution
      # headers (docs/usage.md). Analytics (enableAnalytics) is already opt-in.
      # Assigned as a default so the runtime override stays available.
      export PI_TELEMETRY="''${PI_TELEMETRY-0}"

      # The packaged subagent forwards these paths when it bypasses this wrapper.
      export DOTFILES_PI_EXTENSIONS=${lib.escapeShellArg (builtins.toJSON pluginPaths)}

      # pi only recognises its package subcommands as the first argument, and
      # rejects `-e` after them, so those run without the plugin flags.
      flags=(${pluginFlags})
      skip_version_check=1
      case "''${1-}" in
      install | remove | uninstall | update | list | config | mcp)
        flags=()
        skip_version_check=
        ;;
      esac

      # pi never installs an update on its own, but every start pings
      # pi.dev/api/latest-version and nags about newer releases. Turned off, so
      # updates only ever happen when `pi update` is run — which resolves the
      # release to install through that same check, hence the exception above.
      export PI_SKIP_VERSION_CHECK="''${PI_SKIP_VERSION_CHECK-$skip_version_check}"

      ${lib.optionalString selfUpdates ''
        pnpm_home="''${PNPM_HOME:-${defaultPnpmHome}}"
        # Add node and pnpm to PATH for the Pi installation in the user directory.
        use_pnpm() {
          export PNPM_HOME="$pnpm_home"
          export PATH="$pnpm_home/bin:$pnpm_home:${
            lib.makeBinPath [
              nodejs
              pnpm
            ]
          }:$PATH"
        }
      ''}

      run_pi() {
        local pi_bin="$1"
        shift
        ${lib.optionalString (helpSections != "") ''
          # Add local server settings after Pi's own help.
          if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
            "$pi_bin" "''${flags[@]}" "$@"
            printf '%s\n' ${lib.escapeShellArg "\n${helpSections}"}
            exit 0
          fi
        ''}
        exec "$pi_bin" "''${flags[@]}" "$@"
      }

      ${lib.optionalString selfUpdates ''
        # If the user directory contains a Pi installation, use it.
        # pnpm 11 puts the commands in $PNPM_HOME/bin. Versions before pnpm 11 use $PNPM_HOME.
        for user_pi in "$pnpm_home/bin/pi" "$pnpm_home/pi"; do
          if [ -x "$user_pi" ]; then
            use_pnpm
            run_pi "$user_pi" "$@"
          fi
        done

        # The Nix store copy cannot update itself. Install Pi in the user directory.
        # The loop above selects this installation when Pi starts again.
        if [ "''${1-}" = update ]; then
          use_pnpm
          exec pnpm install -g \
            --ignore-scripts --config.minimumReleaseAge=0 ${npmPackage}
        fi
      ''}

      run_pi ${lib.getExe pi-coding-agent} "$@"
    '';
  };
  configSync = import ./config-sync {
    inherit
      lib
      runCommand
      writeShellScriptBin
      nodejs
      pi-coding-agent
      ;
  };
in

# Wrapped in a derivation of its own only to keep the versioned name (a
# writeShellApplication is named after its binary).
runCommand "pi-with-plugins-${pi-coding-agent.version}"
  {
    # Plugins stay reachable (e.g. `pi.plugins.pi-llama`) so nix-update can
    # bump their pins in CI without dedicated flake outputs.
    passthru = {
      inherit plugins configSync modelsCatalog browserEnabled;
      skills = import ./skills.nix { inherit lib tavily-cli; };
    };
    meta = pi-coding-agent.meta // {
      mainProgram = "pi";
      description = "pi-coding-agent bundled with plugins";
    };
  }
  ''
    mkdir -p $out/bin $out/share/fish/vendor_completions.d
    cp ${./completions/pi.fish} $out/share/fish/vendor_completions.d/pi.fish
    ln -s ${lib.getExe wrapper} $out/bin/pi
  ''
