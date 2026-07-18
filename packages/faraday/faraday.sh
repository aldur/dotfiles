#!/usr/bin/env bash
set -euo pipefail

# @describe Run a command with no network access except to allowed destinations
#
# Networking inside the sandbox is removed at the kernel level
# (bubblewrap --unshare-net); each --allow HOST:PORT punches exactly one
# hole back out via a socat relay over a Unix domain socket. Two
# different addresses are involved:
#
#     HOST:PORT       the real destination, dialed by the host-side relay
#     127.0.0.1:PORT  the door inside the sandbox; point the app HERE
#
# Example, pi against a local llama.cpp server:
#     faraday --allow 192.168.64.1:8080 -- \
#         env LLAMA_BASE_URL=http://127.0.0.1:8080/v1 pi
#
# With no --allow, the command runs fully offline.
#
# The filesystem is read-only (and /tmp is a fresh tmpfs); pass --rw for
# each path the command must write.
# @option -a --allow* <HOST:PORT>  Destination reachable from inside the sandbox
# @option --local-port* <PORT>     In-sandbox port for the Nth --allow (default: the allowed port)
# @option --rw* <PATH>             Writable bind mount
# @option --mask* <PATH>           Hide PATH behind an empty tmpfs (takes precedence over --rw)
# @option -m --map* <HOST>         Resolve HOST to 127.0.0.1 inside the sandbox (/etc/hosts)
# @flag --writable-home            Make all of $HOME writable (weakens isolation)
# @flag -v --verbose               Show relay diagnostics
# @arg cmd~ Command to run inside the sandbox

# The nix wrapper pins these, but the raw script (`bash faraday.sh …`)
# picks them up from the ambient PATH, where a missing binary otherwise
# fails confusingly: no argc means an empty --argc-eval expansion
# ("missing command"), no socat means a silent relay ("failed to
# start" — its stderr is discarded). bwrap only fails at sandbox
# launch, after the relays are already up.
for dep in argc bwrap socat; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "faraday: required dependency '$dep' not found in PATH" >&2
    exit 1
  }
done

# argc only assigns the variables for options that were actually passed,
# and bash 5.3's nounset chokes on merely-declared arrays, so give every
# one a real (empty/zero) value first.
argc_allow=()
argc_local_port=()
argc_rw=()
argc_mask=()
argc_map=()
argc_cmd=()
argc_writable_home=0
argc_verbose=0
eval "$(argc --argc-eval "$0" "$@")"

err() {
  echo "faraday: $*" >&2
  exit 1
}

[ "${#argc_cmd[@]}" -gt 0 ] || err "missing command; usage: faraday [--allow HOST:PORT] -- CMD..."

verbose=$argc_verbose

hosts=()
dest_ports=()
for dest in "${argc_allow[@]}"; do
  host=${dest%:*}
  port=${dest##*:}
  [[ "$dest" == *:* && "$host" =~ ^[A-Za-z0-9._-]+$ ]] ||
    err "malformed --allow '$dest' (expected HOST:PORT; IPv6 addresses are not supported)"
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] ||
    err "malformed --allow '$dest' (bad port '$port')"
  hosts+=("$host")
  dest_ports+=("$port")
done

[ "${#argc_local_port[@]}" -le "${#hosts[@]}" ] ||
  err "more --local-port options than --allow destinations"

local_ports=()
for i in "${!hosts[@]}"; do
  port=${argc_local_port[$i]:-${dest_ports[$i]}}
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] ||
    err "bad --local-port '$port'"
  local_ports+=("$port")
done

if [ "${#local_ports[@]}" -gt 0 ]; then
  dup=$(printf '%s\n' "${local_ports[@]}" | sort | uniq -d | head -n 1)
  [ -z "$dup" ] || err "in-sandbox port $dup assigned twice; disambiguate with --local-port"
fi

# The sandbox has no DNS, so hostnames resolve host-side, here and once
# more when the relay dials out. This doubles as a reachability check so
# a down/misspelled destination fails loudly at launch instead of as
# silent connection resets through the relay.
for i in "${!hosts[@]}"; do
  timeout 3 bash -c "exec 3<>/dev/tcp/${hosts[$i]}/${dest_ports[$i]}" 2>/dev/null ||
    err "cannot reach ${hosts[$i]}:${dest_ports[$i]} from the host"
done

relay_dir=$(mktemp -d "${TMPDIR:-/tmp}/faraday.XXXXXX")
relay_pids=()
child=

cleanup() {
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
    kill "$child" 2>/dev/null || true
  fi
  for pid in "${relay_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$relay_dir"
}
trap cleanup EXIT

# Host-side relays: one Unix socket per allowed destination, forwarded
# to the real address. Unix sockets cross the network-namespace boundary
# through the filesystem, which is the whole trick.
socks=()
for i in "${!hosts[@]}"; do
  sock="$relay_dir/$i.sock"
  if [ "$verbose" = 1 ]; then
    socat -d -d "UNIX-LISTEN:$sock,fork" "TCP:${hosts[$i]}:${dest_ports[$i]}" &
  else
    socat "UNIX-LISTEN:$sock,fork" "TCP:${hosts[$i]}:${dest_ports[$i]}" 2>/dev/null &
  fi
  relay_pids+=("$!")
  socks+=("$sock")
done

for i in "${!socks[@]}"; do
  ready=
  for _ in $(seq 1 100); do
    if [ -S "${socks[$i]}" ]; then
      ready=1
      break
    fi
    sleep 0.05
  done
  [ -n "$ready" ] || err "host-side relay for ${hosts[$i]}:${dest_ports[$i]} failed to start"
done

# --unshare-pid is teardown insurance, not (only) isolation: bwrap keeps
# a supervisor process between us and the sandbox, so a SIGTERM to it
# SIGKILLs the sandbox shell (--die-with-parent) before any trap can
# run. With a pid namespace the kernel reaps every sandboxed process
# when the namespace init dies — nothing can be orphaned.
bwrap_args=(
  --ro-bind / /
  --dev /dev
  --proc /proc
  --tmpfs /tmp
  --bind "$relay_dir" "$relay_dir"
  --unshare-net
  --unshare-pid
  --die-with-parent
)

# glibc sends NSS lookups to nscd through /run/nscd/socket — a Unix
# socket, so it crosses the network namespace via the bound filesystem.
# Left alone it both bypasses the --map /etc/hosts override and hands
# the sandbox host-side DNS resolution (an information side channel out
# of a "no network" jail). Mask it so glibc falls back to files/dns.
if [ -d /run/nscd ]; then
  bwrap_args+=(--tmpfs /run/nscd)
fi

if [ "$argc_writable_home" = 1 ]; then
  bwrap_args+=(--bind "$HOME" "$HOME")
fi

for path in "${argc_rw[@]}"; do
  abs=$(realpath -e -- "$path" 2>/dev/null) || err "--rw path '$path' does not exist"
  bwrap_args+=(--bind "$abs" "$abs")
done

# Masks come after the writable binds so they shadow them. A missing
# path is skipped, not an error: the read-only root means it cannot
# appear later, so there is nothing to hide (and it lets one alias
# list directories that only exist on some machines).
for path in "${argc_mask[@]}"; do
  abs=$(realpath -m -- "$path")
  if [ -d "$abs" ]; then
    bwrap_args+=(--tmpfs "$abs")
  elif [ -e "$abs" ]; then
    bwrap_args+=(--ro-bind /dev/null "$abs")
  fi
done

if [ "${#argc_map[@]}" -gt 0 ]; then
  {
    echo "127.0.0.1 localhost ${argc_map[*]}"
    echo "::1 localhost"
  } >"$relay_dir/hosts"
  # On NixOS /etc/hosts is a symlink into the store; bwrap can only
  # mount over the resolved file, not the symlink.
  bwrap_args+=(--ro-bind "$relay_dir/hosts" "$(readlink -f /etc/hosts)")
fi

# In-sandbox side of the relay: a loopback listener per destination,
# bridged to the host through the Unix socket. bwrap brings `lo` up on
# its own — do NOT bring it up manually; the ioctl fails with EPERM for
# non-root users because bwrap is not setuid.
#
# The listeners must be killed before this shell exits (a fork'ing socat
# runs forever and bwrap would wait on it), so the user command cannot
# be exec'd. It runs in the background with the same signal handling as
# the outer wrapper: SIGINT is left to the terminal to deliver to the
# foreground process group, SIGTERM is forwarded to the command.
#
# Both this inner shell and the outer wrapper background their child —
# and a non-interactive shell reassigns a background job's stdin to
# /dev/null (POSIX), which detaches TUIs from the terminal (observed: pi
# exiting instantly with no output). Explicit redirections are applied
# *after* that assignment, so each level saves the real stdin on fd 3
# and hands it back across the `&`.
inner=$(
  cat <<'EOF'
set -euo pipefail
read -ra ports <<<"$FARADAY_PORTS"
read -ra socks <<<"$FARADAY_SOCKS"

pids=()
cleanup_inner() {
  [ "${#pids[@]}" -eq 0 ] || kill "${pids[@]}" 2>/dev/null || true
}
trap cleanup_inner EXIT

for i in "${!ports[@]}"; do
  if [ "$FARADAY_VERBOSE" = 1 ]; then
    socat -d -d "TCP-LISTEN:${ports[$i]},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${socks[$i]}" &
  else
    socat "TCP-LISTEN:${ports[$i]},bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:${socks[$i]}" 2>/dev/null &
  fi
  pids+=("$!")
done

# Readiness: poll /proc/net/tcp for a LISTEN (0A) entry on each port.
# (Not /sys/class/net — it is bind-mounted from the host and lies; and
# not a probe connection, which would touch the real destination.)
for port in "${ports[@]}"; do
  hex=$(printf '%04X' "$port")
  ready=
  for _ in $(seq 1 100); do
    if grep -q "0100007F:$hex 00000000:0000 0A" /proc/net/tcp; then
      ready=1
      break
    fi
    sleep 0.05
  done
  if [ -z "$ready" ]; then
    echo "faraday: in-sandbox listener on 127.0.0.1:$port failed to start" >&2
    exit 1
  fi
done

exec 3<&0
"$@" <&3 3<&- &
app=$!
trap 'kill -TERM "$app" 2>/dev/null || true' TERM
trap ':' INT

status=0
while :; do
  if wait "$app"; then status=0; else status=$?; fi
  kill -0 "$app" 2>/dev/null || break
done
exit "$status"
EOF
)

exec 3<&0
if [ "${#hosts[@]}" -gt 0 ]; then
  bwrap_args+=(
    --setenv FARADAY_PORTS "${local_ports[*]}"
    --setenv FARADAY_SOCKS "${socks[*]}"
    --setenv FARADAY_VERBOSE "$verbose"
  )
  bwrap "${bwrap_args[@]}" bash -c "$inner" faraday-sandbox "${argc_cmd[@]}" <&3 3<&- &
else
  bwrap "${bwrap_args[@]}" "${argc_cmd[@]}" <&3 3<&- &
fi
child=$!

# SIGINT: stay alive — the terminal delivers Ctrl-C to the foreground
# process group, so the sandboxed command receives it directly and gets
# to decide (a TUI may just cancel an action). If it exits, its status
# propagates below. SIGTERM (aimed at this wrapper): forward it.
trap ':' INT
trap 'kill -TERM "$child" 2>/dev/null || true' TERM

status=0
while :; do
  if wait "$child"; then status=0; else status=$?; fi
  kill -0 "$child" 2>/dev/null || break
done
# An unconditional trailing `exit` makes shellcheck (0.11) forget that
# the EXIT trap invokes cleanup() and flag it as unused (SC2329).
[ "$status" -eq 0 ] || exit "$status"
