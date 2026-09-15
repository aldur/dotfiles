#!/usr/bin/env bash
# Invoked through SSH after reboot, inheriting the managed login shell's environment.
set -euo pipefail
trap 'echo "Login check failed at line $LINENO: $BASH_COMMAND" >&2' ERR
[[ $(id -un) == ubuntu && $HOME == /home/ubuntu ]]
[[ $XDG_RUNTIME_DIR == /run/user/$(id -u) ]]
[[ $EDITOR == nvim ]]
grep -qxF '# pre-existing config' "$HOME/.config/fish/config.fish.before-dotfiles"
grep -qxF preserved "$HOME/unmanaged-marker"
for tool in nix fish git tmux lazyvim rg jq direnv totp-cli age ctags watch rga tree rig difft; do
  command -v "$tool"
done
nix eval --option pure-eval true --raw "path:$HOME/.config/home-manager#homeConfigurations.default.config.home.username" | grep -x ubuntu
systemd-run --user --wait --pipe --collect /bin/sh -eu <<'SH'
test "$HOME" = /home/ubuntu
test "${XDG_CONFIG_HOME:-$HOME/.config}" = "$HOME/.config"
test "$XDG_RUNTIME_DIR" = "/run/user/$(id -u)"
SH
deadline=$((SECONDS + 60))
until systemctl --user is-active --quiet atuin-daemon.service gpg-agent.socket; do
  ((SECONDS < deadline)) || {
    systemctl --user --no-pager status atuin-daemon.service gpg-agent.socket
    exit 1
  }
  sleep 1
done
gpg-connect-agent /bye
export ATUIN_SESSION
ATUIN_SESSION=$(atuin uuid)
entry=$(timeout 30s atuin history start -- 'ubuntu-bootstrap')
timeout 30s atuin history end --exit 0 "$entry"
tmux -L bootstrap new-session -d -s smoke
tmux -L bootstrap show-options -gv prefix | grep -Fx C-a
tmux -L bootstrap kill-server
lazyvim --headless '+qa!'
[[ $(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns) == 1 ]]
mkdir -p "$HOME/workspace"
cd "$HOME/workspace"
# HOME is evaluated inside the sandbox.
# shellcheck disable=SC2016
agent-sandbox -- bash -euc '
  test ! -e "$HOME/unmanaged-marker"
  echo sandbox-ok > sandbox-result
  python3 -c "import socket; assert socket.getaddrinfo(\"localhost\", 443)"
  curl --fail --retry 2 --max-time 30 https://cache.nixos.org/nix-cache-info
'
grep -qxF sandbox-ok sandbox-result
git init signed-commit
cd signed-commit
# Keep the real signing configuration; only the agent contains a test identity.
git commit --allow-empty -m 'Test signing after SSH reconnect'
ssh-add -L | sed 's/^/test@example.invalid namespaces="git" /' >allowed-signers
git -c gpg.ssh.allowedSignersFile="$PWD/allowed-signers" verify-commit HEAD
test -z "$(systemctl --user --failed --no-legend)"
