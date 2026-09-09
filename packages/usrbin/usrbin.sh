#!/usr/bin/env bash
set -euo pipefail

# @describe Run a command with the tools of PATH linked under /usr/bin and /bin
#
# A per-process stand-in for envfs. A script with a fixed shebang such as
# `#!/usr/bin/python3` finds the python3 of the current PATH. bubblewrap
# binds a directory of symlinks over /usr/bin and /bin, in a user
# namespace, so no root is needed. The rest of the filesystem, the
# network and the environment stay those of the caller.
#
# Put `--` before the command, or argc reads its options as its own.
#
# Examples:
#     usrbin -- ./script-with-a-debian-shebang.py
#     usrbin -- python3 --version
#     usrbin                # a shell where /usr/bin/python3 works
# @arg cmd* Command to run. Default: $SHELL

for dep in argc bwrap; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "usrbin: required dependency '$dep' not found in PATH" >&2
    exit 1
  }
done

argc_cmd=()
eval "$(argc --argc-eval "$0" "$@")"

if [ "${#argc_cmd[@]}" -eq 0 ]; then
  argc_cmd=("${SHELL:-bash}")
fi

links=$(mktemp -d)
trap 'rm -rf "$links"' EXIT

# The first match on PATH wins, as in the shell. /bin and /usr/bin are
# the mount points, so they do not count, as in envfs.
IFS=: read -ra dirs <<<"$PATH"
for dir in "${dirs[@]}"; do
  case "$dir" in
  /bin | /usr/bin | /bin/ | /usr/bin/) continue ;;
  /*) ;;
  *) continue ;;
  esac
  [ -d "$dir" ] || continue
  for tool in "$dir"/*; do
    name=${tool##*/}
    [ -x "$tool" ] || continue
    [ -L "$links/$name" ] && continue
    ln -s -- "$tool" "$links/$name"
  done
done

bwrap --dev-bind / / \
  --ro-bind "$links" /usr/bin \
  --ro-bind "$links" /bin \
  --die-with-parent \
  -- "${argc_cmd[@]}"
