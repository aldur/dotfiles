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
  # Disable hooks globally: a bogus hooksPath means git finds no hooks to run.
  # Re-enable per repository with e.g. `git config core.hooksPath .husky`.
  core.hooksPath = "/dev/null";
  column.ui = "auto";
  branch.sort = "-committerdate";
  merge.conflictStyle = "zdiff3";
  diff.algorithm = "histogram";
  difftool.prompt = false;
  transfer.fsckobjects = true;
  fetch.fsckobjects = true;
  receive.fsckObjects = true;
}
