#!/usr/bin/env bash
{
  set -euo pipefail

  die() {
    echo "$*" >&2
    exit 1
  }
  source_ref=github:aldur/dotfiles
  config_dir="$HOME/.config/home-manager"
  backup=before-dotfiles
  while (($#)); do
    case "$1" in
    --source)
      source_ref=${2:?expected flake reference}
      shift 2
      ;;
    --config)
      config_dir=${2:?expected configuration directory}
      shift 2
      ;;
    --backup-extension)
      backup=${2:?expected backup extension}
      shift 2
      ;;
    *) die "Usage: $0 [--source FLAKE] [--config DIRECTORY] [--backup-extension EXTENSION]" ;;
    esac
  done

  [[ $(id -u) != 0 ]] || die 'Run as your login user, without sudo; the script uses sudo where needed.'
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || die 'This setup is tested on Ubuntu 24.04 LTS.'
  case $(uname -m) in
  x86_64) system=x86_64-linux ;;
  aarch64) system=aarch64-linux ;;
  *) die 'Expected x86-64 or ARM64 Linux.' ;;
  esac
  username=$(id -un)
  account_home=$(getent passwd "$username" | cut -d: -f6)
  [[ $HOME == "$account_home" && -O $HOME ]] || die "HOME must be the account's own home: $account_home"
  [[ $backup != */* && -n $backup ]] || die 'Backup extension must be a filename suffix.'
  [[ -d /run/systemd/system ]] || die 'A running systemd host is required.'
  [[ ${XDG_CONFIG_HOME:-$HOME/.config} == "$HOME/.config" ]] || die 'XDG_CONFIG_HOME must use the account home (~/.config).'
  [[ ${XDG_RUNTIME_DIR:-} == "/run/user/$(id -u)" ]] || die 'Use a normal SSH or console login with a systemd user session.'
  # PAM and environment generators can give services different paths from the shell.
  systemd-run --user --wait --pipe --collect /bin/sh -eu <<'SH'
test "$HOME" = "$(getent passwd "$(id -un)" | cut -d: -f6)"
test "${XDG_CONFIG_HOME:-$HOME/.config}" = "$HOME/.config"
test "$XDG_RUNTIME_DIR" = "/run/user/$(id -u)"
SH

  # Check an actual command: sudo -v can demand a password even when commands
  # are allowed without one (Ubuntu cloud images also match the sudo group rule).
  sudo true
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl xz-utils python3 apparmor
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck source=/dev/null
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  if ! command -v nix >/dev/null; then
    echo 'Installing multi-user Nix...'
    curl --fail --location --retry 3 https://releases.nixos.org/nix/nix-2.34.8/install -o "$work/install-nix"
    sh "$work/install-nix" --daemon --yes --no-channel-add
    # shellcheck source=/dev/null
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  systemctl is-active --quiet nix-daemon.socket || die 'The multi-user Nix daemon socket is not active.'
  # Enable flakes without replacing the installer configuration.
  if ! sudo grep -qxF 'extra-experimental-features = nix-command flakes' /etc/nix/nix.conf; then
    echo 'extra-experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf >/dev/null
    sudo systemctl restart nix-daemon.service
  fi

  mkdir -p "$config_dir"
  config_dir=$(realpath "$config_dir")
  if [[ ! -e $config_dir/flake.nix ]]; then
    # JSON carries account data without interpreting it as shell or Nix code.
    python3 - "$config_dir" "$source_ref" "$system" "$username" "$HOME" <<'PY'
import json
import pathlib
import sys

directory, source, system, username, home = sys.argv[1:]
directory = pathlib.Path(directory)
source = json.dumps(source).replace("${", "\\${")
(directory / "host.json").write_text(json.dumps({
    "system": system, "username": username, "homeDirectory": home,
}, indent=2) + "\n")
(directory / "flake.nix").write_text('''{
  inputs.dotfiles.url = SOURCE;
  outputs = { dotfiles, ... }:
    let
      host = builtins.fromJSON (builtins.readFile ./host.json);
      home = dotfiles.lib.mkHome host;
    in {
      lib.installBwrapPolicy = "${dotfiles}/base_hosts/home-manager/install-bwrap-policy.sh";
      homeConfigurations.default = home;
      packages.${host.system}.default = home.activationPackage;
      apps.${host.system}.default = {
        type = "app";
        program = "${home.activationPackage}/activate";
      };
    };
}
'''.replace("SOURCE", source))
PY
  fi

  echo "Building the configuration in $config_dir (pure evaluation)..."
  nix build --option pure-eval true --out-link "$config_dir/result" "path:$config_dir"
  generation=$(readlink -f "$config_dir/result")
  # Read host integration from the same configuration that was just built.
  # Interpolation in --apply belongs to Nix.
  # shellcheck disable=SC2016
  nix eval --option pure-eval true --raw "path:$config_dir#homeConfigurations.default" \
    --apply 'home: home.pkgs.lib.toShellVars {
    configured_user = home.config.home.username;
    configured_home = home.config.home.homeDirectory;
    bwrap = "${home.pkgs.bubblewrap}/bin/bwrap";
  }' >"$work/host.env"
  configured_user='' configured_home='' bwrap=''
  # shellcheck source=/dev/null
  source "$work/host.env"
  [[ $configured_user == "$username" && $configured_home == "$HOME" ]] || die 'The existing configuration targets a different account.'
  policy_installer=$(nix eval --option pure-eval true --raw "path:$config_dir#lib.installBwrapPolicy")
  bash "$policy_installer" "$bwrap"

  echo "Activating; conflicting files get the .$backup suffix."
  HOME_MANAGER_BACKUP_EXT="$backup" "$generation/activate"

  # Use the stable profile path so changing generations does not break login.
  fish="$HOME/.nix-profile/bin/fish"
  [[ -x $fish ]] || die "The generation did not install $fish"
  if ! grep -qxF "$fish" /etc/shells; then
    printf '%s\n' "$fish" | sudo tee -a /etc/shells >/dev/null
  fi
  sudo usermod --shell "$fish" "$username"
  echo "Setup complete. Reconnect over SSH to start Fish. Configuration: $config_dir"
}
