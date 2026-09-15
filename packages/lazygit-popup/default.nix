{
  lib,
  writeShellApplication,
  formats,
  tmux,
  lazygit,
  # The user's lazygit settings. The popup config is these plus the `q`
  # custom command, so the popup keeps every other setting.
  settings ? { },
}:

let
  # Custom commands take precedence over the built-in binding, so `q`
  # backgrounds the popup instead of quitting. Resolve the popup's own session
  # live (#S) and target it with -s: a bare `detach-client` would pick the
  # outer terminal and drop the user out of tmux entirely. Absolute paths,
  # because the command runs with the tmux server's PATH.
  detachPopup = {
    key = "q";
    context = "global";
    description = "Background (hide tmux popup)";
    command = ''${lib.getExe tmux} detach-client -s "$(${lib.getExe tmux} display-message -p '#S')"'';
  };

  configFile = (formats.yaml { }).generate "lazygit-popup-config.yml" (
    settings
    // {
      customCommands = (settings.customCommands or [ ]) ++ [ detachPopup ];
    }
  );
in
writeShellApplication {
  name = "lazygit-popup";

  runtimeInputs = [
    tmux
  ];

  runtimeEnv = {
    LAZYGIT_BIN = lib.getExe lazygit;
    LAZYGIT_POPUP_CONFIG = configFile;
  };

  text = builtins.readFile ./lazygit-popup.sh;
}
