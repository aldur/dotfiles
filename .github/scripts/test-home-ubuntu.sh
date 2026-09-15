#!/usr/bin/env bash
# Run only on an ephemeral Ubuntu runner or disposable VM: this creates an account
# and installs one AppArmor policy. It never disables user-namespace restrictions.
set -euo pipefail

[[ ${GITHUB_ACTIONS:-} == true || ${DOTFILES_HOME_TEST_DISPOSABLE:-} == 1 ]] || {
  echo 'Run on GitHub Actions, or set DOTFILES_HOME_TEST_DISPOSABLE=1 in a disposable Ubuntu VM.' >&2
  exit 1
}
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]]
system=${1:?expected Nix system}
: "${RUNNER_TEMP:?}" "${SIGNING_KEYS:?}"
work="$RUNNER_TEMP/home-manager-ci"
logs="$work/logs"
mkdir -p "$logs"
repo="path:$PWD"
nix_args=(--option pure-eval true --no-write-lock-file
  --override-input gh-signing-keys "file+file://$SIGNING_KEYS")

home_user=''
home_dir=''
home_uid=''
nix_bin=''
# Filled by Nix's shell-escaped configuration records below.
bwrap='' configured_system='' expected_git_name='' expected_git_email=''
custom_drv='' custom_git_email=''
run_home() {
  sudo --user="$home_user" env -i HOME="$home_dir" USER="$home_user" LOGNAME="$home_user" \
    PATH="$home_dir/.nix-profile/bin:$nix_bin:/usr/bin:/bin" \
    TERM=xterm-256color LC_ALL=C.UTF-8 \
    XDG_RUNTIME_DIR="/run/user/$home_uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$home_uid/bus" \
    /bin/sh -c 'cd "$HOME" && exec "$@"' home-test "$@"
}
# Activation can return while a service is still starting or restarting.
wait_home_unit() {
  local unit=$1 state deadline=$((SECONDS + 60))
  while true; do
    state=$(run_home /usr/bin/systemctl --user show "$unit" --property=ActiveState --value)
    case "$state" in
    active) return 0 ;;
    failed) break ;;
    esac
    ((SECONDS < deadline)) || break
    sleep 1
  done
  echo "$unit did not become active (last state: $state)." >&2
  run_home /usr/bin/systemctl --user --no-pager --full status "$unit" >&2 || true
  return 1
}

report() {
  result=$?
  trap - EXIT
  if [[ -n $home_uid ]]; then
    run_home /usr/bin/systemctl --user --no-pager --failed >"$logs/failed-services.txt" 2>&1 || true
    # The runner owns the logs; only reading the journal needs root.
    # shellcheck disable=SC2024
    sudo journalctl --no-pager "_UID=$home_uid" -n 300 >"$logs/user-journal.txt" 2>&1 || true
  fi
  # shellcheck disable=SC2024
  sudo journalctl -k --no-pager -n 200 >"$logs/kernel-journal.txt" 2>&1 || true
  if ((result != 0)); then
    tail -n 60 "$logs"/*.log 2>/dev/null || true
    tail -n 100 "$logs/user-journal.txt" 2>/dev/null || true
  fi
  exit "$result"
}
trap report EXIT

# Resolve the native output through the same #home interface used by users.
echo 'Building the default home generation...'
generation=$(nix build "${nix_args[@]}" --no-link --print-out-paths "$repo#home")
activation=$(nix eval "${nix_args[@]}" --raw "$repo#apps.$system.home.program")
[[ $activation == "$generation/activate" && -x $activation ]]
home_config="$repo#legacyPackages.$system.homeConfiguration"
# Interpolation inside this expression belongs to Nix.
# shellcheck disable=SC2016
nix eval "${nix_args[@]}" --raw "$home_config" --apply 'home: home.pkgs.lib.toShellVars {
  configured_system = home.pkgs.stdenv.hostPlatform.system;
  home_user = home.config.home.username;
  home_dir = home.config.home.homeDirectory;
  expected_git_name = home.config.programs.git.settings.user.name;
  expected_git_email = home.config.programs.git.settings.user.email;
  bwrap = "${home.pkgs.bubblewrap}/bin/bwrap";
}' >"$work/home.env"
# shellcheck source=/dev/null
source "$work/home.env"
[[ $configured_system == "$system" ]]
nix_bin=$(dirname "$(readlink -f "$(command -v nix)")")
# A pre-existing account would make this an unsafe and misleading test.
if id "$home_user" &>/dev/null; then
  echo "Refusing to modify existing account $home_user" >&2
  home_user=''
  exit 1
fi
# Runner images put runner-specific XDG paths in /etc/environment, which PAM
# and systemd's environment generator also apply to newly created users.
# Remove them before starting this disposable account's user manager.
# https://github.com/actions/runner-images/issues/14649
sudo sed -i -E '/^[[:space:]]*(XDG_CONFIG_HOME|XDG_RUNTIME_DIR)=/d' /etc/environment
sudo useradd --create-home --home-dir "$home_dir" --shell /bin/bash "$home_user"
home_uid=$(id -u "$home_user")
sudo loginctl enable-linger "$home_user"
sudo systemctl start "user@$home_uid.service"
# Check the service manager's environment, not just run_home's clean shell.
run_home /usr/bin/systemd-run --user --wait --pipe --collect \
  --setenv="EXPECTED_HOME=$home_dir" /bin/sh -eu >"$logs/manager-environment.log" 2>&1 <<'SH'
test "$HOME" = "$EXPECTED_HOME"
test "${XDG_CONFIG_HOME:-$HOME/.config}" = "$HOME/.config"
test "$XDG_RUNTIME_DIR" = "/run/user/$(id -u)"
printf 'User service paths: HOME=%s, XDG_CONFIG_HOME=%s, XDG_RUNTIME_DIR=%s\n' \
  "$HOME" "${XDG_CONFIG_HOME:-$HOME/.config}" "$XDG_RUNTIME_DIR"
SH
run_home mkdir -p "$home_dir/.local/state/nix/profiles" "$home_dir/.config/fish" "$home_dir/workspace"
run_home /bin/bash -euo pipefail <<'SH'
printf '# existing fish config\n' > "$HOME/.config/fish/config.fish"
printf 'keep me\n' > "$HOME/unmanaged-marker"
SH

# Collision protection must abort before changing existing files.
echo 'Checking file protection and repeated activation...'
if run_home "$activation" >"$logs/collision.log" 2>&1; then
  echo 'Activation unexpectedly overwrote an unmanaged configuration.' >&2
  exit 1
fi
grep -E 'would be clobbered|would clobber|Existing file' "$logs/collision.log"
run_home grep -Fx '# existing fish config' "$home_dir/.config/fish/config.fish"

# Opt into backup, then repeat activation to catch profile/service idempotence.
run_home env HOME_MANAGER_BACKUP_EXT=before-dotfiles "$activation" >"$logs/activation.log" 2>&1
run_home "$activation" >"$logs/reactivation.log" 2>&1
run_home grep -Fx '# existing fish config' "$home_dir/.config/fish/config.fish.before-dotfiles"
run_home grep -Fx 'keep me' "$home_dir/unmanaged-marker"
[[ $(run_home readlink -f "$home_dir/.local/state/nix/profiles/home-manager") == "$generation" ]]
echo 'Checking user tools and services...'
run_home env EXPECTED_GIT_NAME="$expected_git_name" EXPECTED_GIT_EMAIL="$expected_git_email" /bin/bash -euo pipefail >"$logs/tools.log" 2>&1 <<'SH'
# Home Manager's session initialization assumes ordinary shell unset-variable handling.
set +u
. "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
set -u
for tool in fish git tmux lazyvim rg jq direnv totp-cli age ctags watch rga tree rig difft; do
  command -v "$tool"
done
test "$(git config --global user.name)" = "$EXPECTED_GIT_NAME"
test "$(git config --global user.email)" = "$EXPECTED_GIT_EMAIL"
fish -ic 'type -q ta; and type -q tls'
tmux -L home-ci new-session -d -s smoke
tmux -L home-ci show-options -gv prefix | grep -Fx C-a
tmux -L home-ci kill-server
lazyvim --headless '+qa!'
SH
{
  wait_home_unit atuin-daemon.service
  wait_home_unit gpg-agent.socket
  run_home gpg-connect-agent /bye
  # Exercise the daemon through its client, with a bound on an unresponsive socket.
  run_home /usr/bin/timeout 30s /bin/bash -euo pipefail <<'SH'
export ATUIN_SESSION
ATUIN_SESSION=$(atuin uuid)
entry=$(atuin history start -- 'home-manager-ci')
test -n "$entry"
atuin history end --exit 0 "$entry"
SH
} >"$logs/services.log" 2>&1

# Ubuntu's scoped userns allowance for this exact Nix-store bwrap. Keep the
# global AppArmor policy active, unlike the separate nested-sandbox check job.
restriction_before=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
cat >"$work/bwrap.apparmor" <<POLICY
abi <abi/4.0>,
include <tunables/global>
profile dotfiles-home-ci-bwrap "$bwrap" flags=(unconfined) {
  userns,
}
POLICY
sudo install -m 644 "$work/bwrap.apparmor" /etc/apparmor.d/dotfiles-home-ci-bwrap
sudo apparmor_parser -r /etc/apparmor.d/dotfiles-home-ci-bwrap
[[ $(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns) == "$restriction_before" ]]

# Exercise lib.mkHome customization and a second generation, including agents.
echo 'Building the customized home generation...'
custom_options="{
  system = \"$system\";
  modules = [{
    identity.email = \"home-manager-ci@example.invalid\";
    programs.aldur.claude-code.enable = true;
    programs.aldur.codex.enable = true;
  }];
}"
nix eval "${nix_args[@]}" --raw "$repo#lib.mkHome" \
  --apply "mkHome: let home = mkHome $custom_options; in home.pkgs.lib.toShellVars {
    custom_drv = home.activationPackage.drvPath;
    custom_git_email = home.config.programs.git.settings.user.email;
  }" >"$work/custom.env"
# shellcheck source=/dev/null
source "$work/custom.env"
custom=$(nix build --option pure-eval true --no-link --print-out-paths "$custom_drv^*")
run_home "$custom/activate" >"$logs/custom-activation.log" 2>&1
[[ $(run_home readlink -f "$home_dir/.local/state/nix/profiles/home-manager") == "$custom" ]]
echo 'Checking the customized environment and sandbox...'
run_home env EXPECTED_GIT_EMAIL="$custom_git_email" /bin/bash -euo pipefail >"$logs/sandbox.log" 2>&1 <<'SH'
set +u
. "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
set -u
test "$(git config --global user.email)" = "$EXPECTED_GIT_EMAIL"
cd "$HOME/workspace"
printf 'workspace data\n' > visible
agent-sandbox -- bash -euo pipefail <<'SANDBOX'
test -r visible
test ! -e "$HOME/unmanaged-marker"
printf 'sandbox write\n' > written
python3 -c 'import socket; assert socket.getaddrinfo("localhost", 443)'
curl --fail --retry 2 --max-time 30 https://cache.nixos.org/nix-cache-info
SANDBOX
grep -Fx 'sandbox write' written
agent-sandbox --profile codex -- codex --version
agent-sandbox --profile claude -- claude --version
SH

# The original generation must remain usable after a customized one.
run_home "$activation" >"$logs/rollback.log" 2>&1
[[ $(run_home readlink -f "$home_dir/.local/state/nix/profiles/home-manager") == "$generation" ]]
run_home git config --global --get user.email | grep -Fx "$expected_git_email"
wait_home_unit atuin-daemon.service
printf 'Ubuntu %s: activation, customization, services, sandbox and rollback passed.\n' "$system"
