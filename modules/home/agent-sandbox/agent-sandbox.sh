#!/usr/bin/env bash
set -euo pipefail

# @describe Run a command with an explicit filesystem and socket allowlist
# @option --profile <NAME> Mount profile (default: generic tools, no agent state)
# @option --workspace <DIR> Writable workspace (default: launch directory)
# @option --ro* <PATH> Additional existing read-only file or directory
# @option --rw* <PATH> Additional existing writable file or directory
# @option --env* <NAME> Additional inherited environment variable (repeatable)
# @arg cmd~ Command to run inside the sandbox (required)

# @sandbox-configuration@

# Configuration and pinned tools are supplied by package.nix. Initialize
# arrays even when an option is absent, as in the other argc-based wrappers.
argc_profile=default
argc_workspace=$PWD
argc_ro=()
argc_rw=()
argc_env=()
argc_cmd=()
eval "$(argc --argc-eval "$0" "$@")"

die() {
  printf '%s: %s\n' "$sandbox_name" "$*" >&2
  exit 1
}

[ "${#argc_cmd[@]}" -gt 0 ] || die "missing command; usage: $sandbox_name [--ro PATH] [--rw PATH] -- COMMAND..."
select_profile "$argc_profile"
workspace=$argc_workspace
extra_read_only_paths+=("${argc_ro[@]}")
extra_read_write_paths+=("${argc_rw[@]}")
extra_environment_allowlist+=("${argc_env[@]}")
set -- "${argc_cmd[@]}"

if [ "${AGENT_NO_SANDBOX:-0}" = 1 ]; then
  bypass_var=AGENT_NO_SANDBOX
fi
if [ "${!bypass_var:-0}" = 1 ]; then
  printf '%s: WARNING: %s=1; running without the sandbox.\n' "$sandbox_name" "$bypass_var" >&2
  exec "$@"
fi

# Bubblewrap preserves unrelated inherited descriptors. Close them in an
# already-parsed subshell before exec, including Bash's script descriptor.
# Only interactive/piped stdio crosses the boundary.
close_extra_fds() {
  local descriptor path
  [ -d /proc/self/fd ] || die "cannot enumerate inherited file descriptors"
  for path in /proc/self/fd/*; do
    descriptor=${path##*/}
    case "$descriptor" in
      0 | 1 | 2) continue ;;
    esac
    exec {descriptor}>&-
  done
}

uid=$(id -u)
username=$(id -un)
host_runtime=${XDG_RUNTIME_DIR:-/run/user/$uid}
runtime=/run/user/$uid
home_dir=$(realpath -ms -- "$HOME")
home_source=$(realpath -e -- "$home_dir")

# Expand only a leading ~/, never evaluate shell code from a path option.
expand_path() {
  local path=$1
  case "$path" in
    '~') path=$home_dir ;;
    '~/'*) path="$home_dir/${path:2}" ;;
  esac
  realpath -ms -- "$path"
}

check_grant() {
  local path=$1 resolved candidate
  resolved=$(realpath -e -- "$path") || die "path does not exist: $path"
  # Check the resolved source too, so a symlink cannot turn a small grant
  # into the entire host or home. More specific paths can be added explicitly.
  for candidate in "$path" "$resolved"; do
    if [[ "$home_dir/" == "$candidate/"* || "$home_source/" == "$candidate/"* ]]; then
      die "refusing broad filesystem grant: $path"
    fi
    case "$candidate" in
      / | /home | "$home_dir" | /persist | /tmp | /var | /var/tmp | /run | /nix | /nix/store | /etc | /dev | /proc | /sys)
        die "refusing broad filesystem grant: $path" ;;
    esac
  done
}

workspace=$(expand_path "$workspace")
check_grant "$workspace"
[ -d "$workspace" ] || die "workspace must be a directory: $workspace"

# All host mounts go through this helper. Sources are resolved in the host
# namespace; destinations keep the requested spelling (including ~/ paths).
# Optional built-ins may be absent; user-supplied grants must exist.
mount_args=()
add_mount() {
  local mode=$1 path=$2 optional=${3:-0} source
  path=$(expand_path "$path")
  if [ "$optional" = 1 ] && [ ! -e "$path" ]; then
    return
  fi
  check_grant "$path"
  source=$(realpath -e -- "$path") || die "path does not exist: $path"
  mount_args+=("$mode" "$source" "$path")
}

# System tools and configuration. /nix/store is the only mandatory host tree.
for path in "${system_read_only_paths[@]}" "/etc/profiles/per-user/$username"; do
  add_mount --ro-bind "$path" 1
done
system_mounts=("${mount_args[@]}")
mount_args=()

# Writable grants: the workspace, existing state of the selected agent,
# and extra user grants. Everything else in the private home is ephemeral.
add_mount --bind "$workspace"
for path in "${agent_read_write_paths[@]}"; do
  add_mount --bind "$path" 1
done
for path in "${extra_read_write_paths[@]}"; do
  path=$(expand_path "$path")
  check_grant "$path"
  add_mount --bind "$path"
done
writable_mounts=("${mount_args[@]}")
mount_args=()

# Read-only grants are applied after writable ones. Keep installations out
# of writable agent state, and let explicit --ro grants restrict a workspace.
for path in "${user_read_only_paths[@]}" "${agent_read_only_paths[@]}"; do
  add_mount --ro-bind "$path" 1
done
for path in "${extra_read_only_paths[@]}"; do
  path=$(expand_path "$path")
  check_grant "$path"
  add_mount --ro-bind "$path"
done
read_only_mounts=("${mount_args[@]}")

# Runtime mounts grant access to services, regardless of mount writability.
# Reject absolute paths, parent traversal and the unfiltered session bus.
service_mounts=()
nix_environment=()
for entry in "${runtime_allowlist[@]}"; do
  case "/$entry/" in
    //* | */../* | */./* | /bus/*) die "invalid runtime allowlist entry: $entry" ;;
  esac
  if [ -e "$host_runtime/$entry" ]; then
    source=$(realpath -e -- "$host_runtime/$entry")
    service_mounts+=(--bind "$source" "$runtime/$entry")
  fi
done
if [ "$allow_nix_daemon" = 1 ] && [ -S /nix/var/nix/daemon-socket/socket ]; then
  service_mounts+=(
    --bind /nix/var/nix/daemon-socket/socket /nix/var/nix/daemon-socket/socket
  )
  nix_environment=(--setenv NIX_REMOTE daemon)
fi

# The proxy runs outside the sandbox and exports only the filtered socket.
bus_addr=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$host_runtime/bus}
proxy_dir=$(mktemp -d "/tmp/$sandbox_name-dbus-proxy.XXXXXX")
proxy_sock=$proxy_dir/bus
proxy_args=(--filter --talk=org.freedesktop.DBus)
for bus in "${dbus_talk[@]}"; do
  proxy_args+=("--talk=$bus")
done
(
  close_extra_fds
  exec xdg-dbus-proxy "$bus_addr" "$proxy_sock" "${proxy_args[@]}"
) &
proxy_pid=$!
trap 'kill "$proxy_pid" 2>/dev/null || true; rm -rf -- "$proxy_dir"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -S "$proxy_sock" ] && break
  sleep 0.1
done
[ -S "$proxy_sock" ] || die "xdg-dbus-proxy did not come up"
service_mounts+=(--bind "$proxy_sock" "$runtime/bus")

# Start empty. No host root, home, /persist, /tmp or /run bind is inherited.
filesystem_args=(
  --tmpfs /
  --ro-bind /nix/store /nix/store
  --dev /dev
  --proc /proc
  --tmpfs /tmp
  --tmpfs /var/tmp
  --dir "$home_dir"
  --perms 0700 --dir "$home_dir/.gnupg"
  --dir "$runtime"
  --symlink "$sandbox_shell" /bin/sh
  --symlink "$sandbox_shell" /bin/bash
  --symlink "$sandbox_env" /usr/bin/env
)

# Inherit only the tools, terminal and locale settings needed for ordinary
# command execution. Secrets, desktop endpoints and language/shell injection
# settings require an explicit --env NAME or a profile grant.
environment_allowlist=(
  PATH TERM COLORTERM TERMINFO TERMINFO_DIRS LANG LANGUAGE
  LC_ALL LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT
  LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME TZ
  LOCALE_ARCHIVE NIX_LD NIX_LD_LIBRARY_PATH NIX_SSL_CERT_FILE
  SSL_CERT_FILE SSL_CERT_DIR
)
environment_args=(--clearenv)
for name in "${environment_allowlist[@]}" "${extra_environment_allowlist[@]}"; do
  [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "invalid environment variable name: $name"
  if [[ -v "$name" ]]; then
    environment_args+=(--setenv "$name" "${!name}")
  fi
done
# These sandbox locations take precedence even over explicit env grants.
environment_args+=(
  --setenv HOME "$home_dir"
  --setenv USER "$username"
  --setenv LOGNAME "$username"
  --setenv SHELL "$sandbox_shell"
  --setenv TMPDIR /tmp
  --setenv TMP /tmp
  --setenv TEMP /tmp
  --setenv XDG_RUNTIME_DIR "$runtime"
  --setenv XDG_CONFIG_HOME "$home_dir/.config"
  --setenv XDG_CACHE_HOME "$home_dir/.cache"
  --setenv XDG_DATA_HOME "$home_dir/.local/share"
  --setenv XDG_STATE_HOME "$home_dir/.local/state"
  --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$runtime/bus"
  --setenv TMUX_TMPDIR /dev/null
  --setenv GNUPGHOME "$home_dir/.gnupg"
  "${nix_environment[@]}"
)

isolation_args=(
  --die-with-parent --new-session
  --unshare-user --unshare-pid --unshare-ipc --unshare-uts --cap-drop ALL
  --seccomp 3
)

# Keep the wrapper alive so its EXIT trap cleans up the proxy.
(
  close_extra_fds
  exec bwrap \
    "${filesystem_args[@]}" \
    "${system_mounts[@]}" \
    "${writable_mounts[@]}" \
    "${read_only_mounts[@]}" \
    "${service_mounts[@]}" \
    "${environment_args[@]}" \
    "${isolation_args[@]}" \
    --chdir "$workspace" -- "$@" 3< "$seccomp_filter"
)
