{
  lib,
  writeShellApplication,
  formats,
  coreutils,
  tmux-popup-session,
  lazygit,
  # The user's lazygit settings. The popup config is these plus the `q`
  # custom command, so the popup keeps every other setting.
  settings ? { },
}:

let
  # Custom commands take precedence over the built-in binding, so `q`
  # backgrounds the popup instead of quitting. `Q` (and C-c) still quit.
  detachPopup = {
    key = "q";
    context = "global";
    description = "Background (hide tmux popup)";
    command = lib.getExe tmux-popup-session.hide;
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

  text = ''
    exec ${lib.getExe tmux-popup-session} lazygit \
      ${lib.getExe' coreutils "env"} LG_CONFIG_FILE=${configFile} ${lib.getExe lazygit}
  '';
}
