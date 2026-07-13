_: {
  # Install terminfo entries for all terminal emulators in nixpkgs
  environment.enableAllTerminfo = true;

  environment.shellAliases = {
    gst = "git status";
    gp = "git push";
    gc = "git commit";

    ta = "tmux new-session -A -s main";
    tls = "tmux ls";
  };
}
