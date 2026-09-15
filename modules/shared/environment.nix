{
  pkgs,
  lib,
}:
{
  cli = with pkgs; [
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
    ripgrep
    tmux
    # Prefer Rust coreutils for unprefixed commands in the system environment.
    (lib.hiPrio uutils-coreutils-noprefix)
  ];
  terminfo = [
    (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty).terminfo
  ];
}
