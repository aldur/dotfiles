{ pkgs, ... }:
{
  # The terminfo of the terminals in use. Ghostty ships its own entry.
  # iTerm and tmux use entries that ncurses ships. nixpkgs builds ghostty
  # from source for Linux only; the binary release is the darwin package
  # (see modules/darwin/home.nix).
  environment.systemPackages = [
    (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty).terminfo
  ];

  environment.shellAliases = {
    gst = "git status";
    gp = "git push";
    gc = "git commit";

    ta = "tmux new-session -A -s main";
    tls = "tmux ls";
  };
}
