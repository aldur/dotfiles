{ pkgs, ... }:
{
  # CLI utils we want available on all systems.
  environment.systemPackages = with pkgs; [
    age
    bashInteractive
    bat
    coreutils-prefixed
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
  ];
}
