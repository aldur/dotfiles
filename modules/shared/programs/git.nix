# Shared git workflow settings.
# Consumed by home-manager (programs.git.settings) and NixOS (programs.git.config).
{
  push = {
    default = "current";
    autoSetupRemote = true;
    followTags = true;
  };
  pull = {
    default = "current";
    rebase = true;
  };
  rebase.autoStash = true;
  rerere = {
    enabled = true;
    autoUpdate = true;
  };
  # Disable hooks by default; repository settings can override this.
  # Re-enable for trusted repositories with e.g. `git config core.hooksPath .husky`.
  core.hooksPath = "/dev/null";
  # Require --git-dir or GIT_DIR for bare repositories instead of discovering
  # them implicitly inside a checkout. Normal working repositories still work.
  safe.bareRepository = "explicit";
  column.ui = "auto";
  branch.sort = "-committerdate";
  merge.conflictStyle = "zdiff3";
  diff.algorithm = "histogram";
  difftool.prompt = false;
  transfer.fsckobjects = true;
  fetch.fsckobjects = true;
  receive.fsckObjects = true;
}
