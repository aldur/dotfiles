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
  column.ui = "auto";
  branch.sort = "-committerdate";
  merge.conflictStyle = "zdiff3";
  diff.algorithm = "histogram";
  transfer.fsckobjects = true;
  fetch.fsckobjects = true;
  receive.fsckObjects = true;
}
