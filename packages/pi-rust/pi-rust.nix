{
  lib,
  callPackage,
  runCommand,
  writeShellApplication,
  fd,
  ripgrep,
  rustPlatform,
  # Plugin derivations to bundle, keyed by name — the same auto-load
  # affordance as ../pi/pi.nix (pi-rust runs pi's TypeScript extension API on
  # an embedded QuickJS runtime). Empty by default: the one plugin pi bundles,
  # pi-llama, is built in here as the `llamacpp` provider
  # (src/provider_metadata.rs upstream).
  plugins ? { },
}:

# The rest of what pi.nix builds by hand comes in the box here: there is no
# telemetry to turn off, the release-nag probe is patched out at build time
# (see ./pi-agent-rust.nix), and there is no self-managed install to hand
# over to — the binary stays Nix's, and `pi-rust update` only manages
# packages under ~/.pi.
let
  # The overlay has no attribute for the agent. No other package here uses
  # the agent. CI finds it in the `passthru` below.
  pi-agent-rust = callPackage ./pi-agent-rust.nix { inherit rustPlatform; };

  pluginFlags = lib.concatMapStringsSep " " (
    plugin: "-e ${lib.escapeShellArg (plugin.entryPoint or "${plugin}/index.ts")}"
  ) (lib.attrValues plugins);

  # Named pi-rust (not upstream's pi) to coexist with pi on PATH.
  wrapper = writeShellApplication {
    name = "pi-rust";
    text = ''
      # The package-manager subcommands run without the plugin flags,
      # mirroring the pi wrapper's carve-out; pi-rust just has more of them.
      flags=(${pluginFlags})
      case "''${1-}" in
      install | remove | update | update-index | list | config | info | search | doctor | migrate)
        flags=()
        ;;
      esac

      # The find/grep tools shell out to `fd` and `rg` from PATH and silently
      # degrade without them. Appended, so a user-installed copy wins.
      export PATH="$PATH:${
        lib.makeBinPath [
          fd
          ripgrep
        ]
      }"

      exec ${lib.getExe pi-agent-rust} "''${flags[@]}" "$@"
    '';
  };
in

# Wrapped in a derivation of its own only to keep the versioned name (a
# writeShellApplication is named after its binary).
runCommand "pi-rust-with-plugins-${pi-agent-rust.version}"
  {
    # The wrapper has no source. The agent holds the pin. The bump leg
    # `pi-rust.pi-agent-rust` names the agent.
    passthru = { inherit pi-agent-rust; };

    # Unlike pi.nix, no `passthru.plugins`: the CI bump matrix names legs
    # after the plugin attribute, so a plugin shared with `pi.plugins` would
    # mint a duplicate leg. Nothing is bundled by default anyway.
    meta = pi-agent-rust.meta // {
      mainProgram = "pi-rust";
      description = "pi-agent-rust bundled with plugins";
    };
  }
  ''
    mkdir -p $out/bin
    ln -s ${lib.getExe wrapper} $out/bin/pi-rust
  ''
