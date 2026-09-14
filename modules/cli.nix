{ lib, pkgs, ... }:
{
  # CLI utils we want available on all systems.
  environment.systemPackages = with pkgs; [
    age
    aldurs-dotfiles-version
    bashInteractive
    bat
    btop
    curl
    dnsutils
    fd
    file
    htop
    jq
    killall
    less
    pv
    python3
    rig
    ripgrep
    tmux
    totp-cli # use with `instance`
    tree
    # Prefer Rust coreutils for unprefixed commands in the system environment.
    (lib.hiPrio uutils-coreutils-noprefix)
  ];
}
