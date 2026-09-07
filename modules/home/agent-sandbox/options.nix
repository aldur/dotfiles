# Shared NixOS options for each agent profile.
{ lib, pkgs }:
let
  inherit (lib) mkOption types;
in
alias: bypassVar: {
  enable = mkOption {
    type = types.bool;
    default = pkgs.stdenv.hostPlatform.isLinux;
    description = ''
      On Linux, wrap `${alias}` in bubblewrap with an empty root and a
      private home, /tmp and runtime directory. Bind system tools and
      selected configuration read-only, and the launch directory and
      project-scoped agent state read/write. Git metadata is protected.
      Other host paths, including /persist, are absent unless explicitly
      granted. Network access is unchanged; writable workspaces and agent
      state remain persistent.

      Set ${bypassVar}=1 in the environment to bypass the wrapper for a
      single invocation without a rebuild. Bypassing prints a warning.
    '';
  };
  filesystem = {
    readOnlyPaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "~/Documents/reference" ];
      description = ''
        Additional existing files or directories to expose read-only.
        Use absolute paths or ~/ for the invoking user's home; these are
        strings, not Nix path literals, so their contents stay out of the
        Nix store. Read-only mounts are applied after writable mounts.
        The agent-sandbox command applies these paths with the matching
        --profile; it also accepts repeated --ro PATH.
      '';
    };
    readWritePaths = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "~/Work/shared-library" ];
      description = ''
        Additional existing files or directories to expose read/write,
        beyond the launch directory and the selected agent's state.
        Use absolute paths or ~/. Changes affect the host directly.
        Repository metadata protections still apply. Use --git-write for an
        explicit per-launch Git metadata exception; --rw cannot override it.
        The agent-sandbox command applies these paths with the matching
        --profile; it also accepts repeated --rw PATH and --workspace DIR
        to replace the default launch directory.
        Missing paths and broad grants such as / or the whole home fail
        at launch. Paths are never expanded with eval.
      '';
    };
  };
  allowNixDaemon = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Expose the host Nix daemon socket, when present, so builds work with
      the read-only store. The daemon authorizes requests as the invoking
      user; this grants service access, not just access to a file. Disable
      it to omit this socket. Do not use a trusted Nix user for confinement.
    '';
  };
  extraEnvironmentAllowlist = mkOption {
    type = types.listOf types.str;
    default = [ ];
    example = [ "OPENAI_API_KEY" ];
    description = ''
      Additional environment variable names to inherit in this agent's
      profile. Only tools, terminal and locale settings are inherited by
      default. Values come from the launch environment, never the Nix store.
      The wrapper also accepts repeated --env NAME. Sandbox home, temporary
      and runtime locations always take precedence over inherited values.
    '';
  };
  extraRuntimeDirAllowlist = mkOption {
    type = types.listOf types.str;
    default = [ ];
    example = [
      "docker.sock"
      "podman/podman.sock"
    ];
    description = ''
      Entries under $XDG_RUNTIME_DIR to bind into the sandbox (path
      relative to $XDG_RUNTIME_DIR). Declare host-specific sockets or dirs
      that the agent needs.

      Be careful: some entries will allow sandbox escape.
    '';
  };
  extraDbusTalk = mkOption {
    type = types.listOf types.str;
    default = [ ];
    example = [ "org.freedesktop.Notifications" ];
    description = ''
      Additional bus names the sandboxed agent is allowed to TALK to
      via the session bus, on top of the always-on org.freedesktop.DBus
      (which is required for any client's initial Hello() handshake).
    '';
  };
}
