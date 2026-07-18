# faraday

Run a command with **no network access except to explicitly allowed
destinations**. The Linux counterpart of the macOS `faraday` alias
(`sandbox-exec ... (deny network*)`), built on
[bubblewrap](https://github.com/containers/bubblewrap) + `socat`.

```sh
faraday -- some-command                        # fully offline
faraday --allow 192.168.64.1:8080 -- some-command  # offline except one hole
```

## How it works

bubblewrap has no IP/port filtering — only `--unshare-net`, which gives the
sandbox a brand-new, empty network namespace (any outbound `connect()` fails
with `ENETUNREACH`; this is kernel-level, not a firewall). Each
`--allow HOST:PORT` then punches exactly one hole back out with a pair of
`socat` relays bridged over a Unix domain socket, which crosses the namespace
boundary through the *filesystem*, not the network:

```text
sandbox app → 127.0.0.1:PORT → socat → unix socket → socat → HOST:PORT
              (inside netns)                (host side, real network)
```

### The two-address model (read this)

Two different addresses do two different jobs:

- `HOST:PORT` — the **real** destination. Only the host-side relay dials it.
- `127.0.0.1:PORT` — the door **inside** the sandbox. The app must target
  *this*, even though the real server lives elsewhere.

So to let `pi` talk to a llama.cpp server on the VM host:

```sh
faraday --allow 192.168.64.1:8080 -- \
  env LLAMA_BASE_URL=http://127.0.0.1:8080/v1 pi
```

Note the URL says `127.0.0.1`, not `192.168.64.1`. If the app hardcodes the
real hostname and won't let you override the URL, use `--map` to point that
name at the relay inside the sandbox:

```sh
faraday --allow myserver.lan:8080 --map myserver.lan -- some-app
```

## Options

| Option              | Effect                                                                     |
| ------------------- | -------------------------------------------------------------------------- |
| `--allow HOST:PORT` | Reachable destination (repeatable). Hostnames resolve host-side at launch. |
| `--local-port PORT` | In-sandbox port for the Nth `--allow` (default: the allowed port).         |
| `--rw PATH`         | Writable bind mount (repeatable).                                          |
| `--mask PATH`       | Hide `PATH` behind an empty tmpfs (repeatable; wins over `--rw`; missing paths are skipped). |
| `--map HOST`        | Resolve `HOST` to `127.0.0.1` inside the sandbox via `/etc/hosts`.         |
| `--writable-home`   | Bind all of `$HOME` read-write. Convenient, but hands the sandboxed process your whole home directory. |
| `--verbose`         | Show socat/relay diagnostics.                                              |

## Writable-path policy

The default is deliberately tight: the whole filesystem is read-only, `/tmp`
is a fresh private tmpfs, and nothing else is writable. Programs that write
config/locks/caches will fail with `EROFS` until you grant them their paths.
For `pi`, roughly:

```sh
faraday --allow 192.168.64.1:8080 \
  --rw ~/.pi --rw ~/.config --rw ~/.cache --rw ~/.local/state \
  -- env LLAMA_BASE_URL=http://127.0.0.1:8080/v1 pi
```

(`--rw` paths must already exist.) `--writable-home` is the blunt opt-out.

The `sandbox` shell alias (the Linux mirror of the darwin one) builds on
`--mask` to additionally hide personal directories:

```sh
sandbox some-command
# = faraday --mask ~/Documents --mask ~/Desktop --mask ~/Developer \
#           --mask ~/Movies --mask ~/Music --mask ~/Pictures -- some-command
```

## Multiple destinations

Each `--allow` gets its own relay. Local ports default to the allowed ports;
when two destinations share a port, disambiguate with `--local-port`
(positional, Nth `--local-port` pairs with Nth `--allow`):

```sh
faraday --allow hostA:8080 --allow hostB:8080 --local-port 8080 --local-port 8081 -- app
# app reaches hostA:8080 at 127.0.0.1:8080 and hostB:8080 at 127.0.0.1:8081
```

## Caveats / sharp edges

- The sandbox has **no DNS**. Hostname destinations are resolved host-side
  (at launch and per relay connection), so rotating-IP/CDN targets are
  fragile. `--map` covers in-sandbox name lookups via `/etc/hosts`.
- The nscd/nsncd socket (`/run/nscd/socket`) is masked inside the sandbox:
  being a Unix socket it crosses the namespace boundary and would both
  bypass `--map` and hand the sandbox host-side DNS resolution — an
  information side channel out of a "no network" jail.
- Destinations are checked for reachability at launch; a down server is a
  hard error.
- IPv6 destinations are not supported.
- To verify isolation from inside, check `/proc/net/dev` (shows only `lo:`)
  or attempt a real `connect()`. Do **not** trust `ls /sys/class/net` — `/sys`
  is bind-mounted from the host and still shows `eth0`.

## Testing

```sh
nix shell .#faraday nixpkgs#socat -c packages/faraday/test.sh
```

Runs as a non-root user (this matters: root would mask permission bugs like
the loopback-bringup `EPERM`) and covers: relay reachability, everything-else
blocked, read-only root + `--rw`, exit-code propagation, `--map`, and clean
teardown including Ctrl-C.
