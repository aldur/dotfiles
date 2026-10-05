# An explicit filesystem allowlist for the coding agents. The shell helper
# assembles these groups into an empty root, then adds the selected workspace.
# Writable workspaces and agent state are persistent; this is not a rollback
# mechanism. Network access is unchanged.
{ pkgs, lib }:
{
  profiles ? { },
  enableDbus ? true,

  # Apple containers default to locked /proc. They cannot mount fresh procfs in a
  # user namespace (essentially, what bubblewrap does), so this flag is required
  # to keep locked `proc` and still use _some_ of the sandbox (e.g., read-only
  # `git`).
  #
  # WARN: this breaks confidentiality, only enable it in containers.
  #
  # NOTE: Kernel 7.0 and further enable a different way of mounting procfs, which
  # might be compatible. Revisit this once the Kata kernel used by default in
  # Apple containers is bumped.
  dangerouslyInheritProc ? false,
}:
let
  seccompFilter =
    pkgs.runCommandCC "agent-sandbox-seccomp.bpf"
      {
        buildInputs = [ pkgs.libseccomp ];
      }
      ''
        $CC -Wall -Wextra -Werror ${./seccomp.c} -lseccomp -o generate-filter
        ./generate-filter > "$out"
      '';

  defaultProfile = {
    runtimeAllowlist = [ ];
    extraDbusTalk = [ ];
    readOnlyPaths = [ ];
    readWritePaths = [ ];
    agentReadOnlyPaths = [ ];
    agentReadWritePaths = [ ];
    stateKind = "";
    allowNixDaemon = true;
    allowDocker = false;
    extraEnvironmentAllowlist = [ ];
  };

  renderProfile =
    profile:
    let
      cfg = defaultProfile // profile;
    in
    ''
      allow_nix_daemon=${if cfg.allowNixDaemon then "1" else "0"}
      allow_docker=${if cfg.allowDocker then "1" else "0"}
      agent_read_only_paths=(${lib.escapeShellArgs cfg.agentReadOnlyPaths})
      agent_read_write_paths=(${lib.escapeShellArgs cfg.agentReadWritePaths})
      agent_state_kind=${lib.escapeShellArg cfg.stateKind}
      extra_read_only_paths=(${lib.escapeShellArgs cfg.readOnlyPaths})
      extra_read_write_paths=(${lib.escapeShellArgs cfg.readWritePaths})
      runtime_allowlist=(${lib.escapeShellArgs cfg.runtimeAllowlist})
      dbus_talk=(${lib.escapeShellArgs cfg.extraDbusTalk})
      extra_environment_allowlist=(${lib.escapeShellArgs cfg.extraEnvironmentAllowlist})
    '';

  # These are optional across hosts. Never include /etc, /run, /nix or
  # /home wholesale: they contain state and sockets as well as tools.
  systemReadOnlyPaths = [
    "/run/current-system/sw"
    "/nix/var/nix/profiles/default"
    "/lib"
    "/lib64"
    "/etc/passwd"
    "/etc/group"
    "/etc/nsswitch.conf"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/services"
    "/etc/protocols"
    "/etc/localtime"
    "/etc/ssl/certs"
    # NixOS certificate entries point here before reaching /nix/store.
    "/etc/static/ssl/certs"
    "/etc/nix/nix.conf"
    "/etc/nix/registry.json"
    "/etc/direnv"
  ];

  userReadOnlyPaths = [
    "~/.nix-profile"
    "~/.local/state/nix/profiles/profile"
    "~/.local/bin"
    "~/.config/git"
    "~/.gitconfig"
    "~/.config/fish"
    "~/.config/direnv"
  ];

  shellConfig = ''
    sandbox_name=agent-sandbox
    sandbox_shell=${lib.escapeShellArg "${pkgs.bash}/bin/bash"}
    sandbox_env=${lib.escapeShellArg "${pkgs.coreutils}/bin/env"}
    sandbox_python=${lib.escapeShellArg "${pkgs.python3}/bin/python3"}
    sandbox_bwrap=${lib.escapeShellArg "${pkgs.bubblewrap}/bin/bwrap"}
    sandbox_launcher=${./launch.py}
    seccomp_filter=${lib.escapeShellArg "${seccompFilter}"}
    enable_dbus=${if enableDbus then "1" else "0"}
    dangerously_inherit_proc=${if dangerouslyInheritProc then "1" else "0"}

    system_read_only_paths=(${lib.escapeShellArgs systemReadOnlyPaths})
    user_read_only_paths=(${lib.escapeShellArgs userReadOnlyPaths})

    select_profile() {
      case "$1" in
        default)
          ${renderProfile { }}
          ;;
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: profile: ''
            ${lib.escapeShellArg name})
              ${renderProfile profile}
              ;;
          '') profiles
        )}
        *) die "unknown sandbox profile: $1" ;;
      esac
    }
  '';
in
assert !(profiles ? default);
assert lib.assertMsg (lib.versionAtLeast pkgs.bubblewrap.version "0.12.0")
  "agent-sandbox requires Bubblewrap >= 0.12.0 (CVE-2026-87766)";
pkgs.writeArgcApplication {
  name = "agent-sandbox";
  # Paths containing ~/ are literal data; expand_path handles them at launch.
  excludeShellChecks = [ "SC2088" ];
  runtimeInputs = [
    pkgs.bubblewrap
    pkgs.coreutils
  ]
  ++ lib.optional enableDbus pkgs.xdg-dbus-proxy;
  meta = {
    description = "Run commands with an explicit filesystem and socket allowlist";
    platforms = lib.platforms.linux;
  };
  text = lib.replaceStrings [ "# @sandbox-configuration@" ] [ shellConfig ] (
    builtins.readFile ./agent-sandbox.sh
  );
}
