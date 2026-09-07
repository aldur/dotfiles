# An explicit filesystem allowlist for the coding agents. The shell helper
# assembles these groups into an empty root, then adds the selected workspace.
# Writable workspaces and agent state are persistent; this is not a rollback
# mechanism. Network access is unchanged.
{ pkgs, lib }:
{
  profiles ? { },
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
    bypassVar = "AGENT_NO_SANDBOX";
    runtimeAllowlist = [ ];
    extraDbusTalk = [ ];
    readOnlyPaths = [ ];
    readWritePaths = [ ];
    agentReadOnlyPaths = [ ];
    agentReadWritePaths = [ ];
    allowNixDaemon = true;
    extraEnvironmentAllowlist = [ ];
  };

  renderProfile =
    profile:
    let
      cfg = defaultProfile // profile;
    in
    ''
      bypass_var=${lib.escapeShellArg cfg.bypassVar}
      allow_nix_daemon=${if cfg.allowNixDaemon then "1" else "0"}
      agent_read_only_paths=(${lib.escapeShellArgs cfg.agentReadOnlyPaths})
      agent_read_write_paths=(${lib.escapeShellArgs cfg.agentReadWritePaths})
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
    "/etc/nix/nix.conf"
    "/etc/nix/registry.json"
  ];

  userReadOnlyPaths = [
    "~/.nix-profile"
    "~/.local/state/nix/profiles/profile"
    "~/.local/bin"
    "~/.config/git"
    "~/.gitconfig"
    "~/.config/fish"
  ];

  shellConfig = ''
    sandbox_name=agent-sandbox
    sandbox_shell=${lib.escapeShellArg "${pkgs.bash}/bin/bash"}
    sandbox_env=${lib.escapeShellArg "${pkgs.coreutils}/bin/env"}
    seccomp_filter=${lib.escapeShellArg "${seccompFilter}"}

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
pkgs.writeArgcApplication {
  name = "agent-sandbox";
  # Paths containing ~/ are literal data; expand_path handles them at launch.
  excludeShellChecks = [ "SC2088" ];
  runtimeInputs = [
    pkgs.bubblewrap
    pkgs.coreutils
    pkgs.xdg-dbus-proxy
  ];
  meta = {
    description = "Run commands with an explicit filesystem and socket allowlist";
    platforms = lib.platforms.linux;
  };
  text = lib.replaceStrings [ "# @sandbox-configuration@" ] [ shellConfig ] (
    builtins.readFile ./agent-sandbox.sh
  );
}
