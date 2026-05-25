# Single source of truth for user-level state crostini and bee both
# preserve across a tmpfs/wipe of /home. Pure data; consumers build
# their preservation block from it.
{
  base = [
    "Documents/"
    "Work/"
    ".local/state/nix"
    ".local/state/lazygit"
    ".local/share/atuin"
    ".local/share/dasht"
    ".local/share/direnv"
    ".local/share/fish"
    {
      directory = ".ssh";
      mode = "0700";
    }
  ];

  lazyvim = [ ".local/state/lazyvim" ];
  llm = [ ".config/io.datasette.llm" ];

  claudeDirectories = [
    ".claude"
    ".local/share/claude/versions"
  ];

  claudeFiles = [ ".claude.json" ];

  # tmpfiles entries for parent directories under /home/<user> are
  # derived from the persisted-paths list in preservation-user.nix.
  # No need to enumerate them here.
}
