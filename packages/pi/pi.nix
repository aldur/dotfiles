{
  lib,
  stdenv,
  runCommand,
  writeShellApplication,
  writeShellScriptBin,
  nodejs,
  pnpm,
  pi-coding-agent,
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

  # Same spirit as the codex wrapper (modules/home/codex): the Nix build
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
        ${lib.optionalString (plugins ? pi-llama) ''
          # Add local server settings after Pi's own help.
          if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
            "$pi_bin" "''${flags[@]}" "$@"
            printf '%s\n' ${lib.escapeShellArg ''

              llama.cpp provider:
                LLAMA_BASE_URL  Server API URL, including /v1.
                                Default: http://localhost:8080/v1
                                Apple Container default: http://192.168.64.1:8080/v1
                                faraday-pi default: http://127.0.0.1:8080/v1

                Set LLAMA_BASE_URL to override the default:
                  LLAMA_BASE_URL=http://my-server:8080/v1 pi
            ''}
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
    passthru = { inherit plugins configSync; };
    meta = pi-coding-agent.meta // {
      mainProgram = "pi";
      description = "pi-coding-agent bundled with plugins";
    };
  }
  ''
    mkdir -p $out/bin
    ln -s ${lib.getExe wrapper} $out/bin/pi
  ''
