{
  lib,
  writeShellApplication,
  coreutils,
  tmux-popup-session,
  taskmd-ui,
}:

writeShellApplication {
  name = "taskmd-ui-popup";

  text = ''
    exec ${lib.getExe tmux-popup-session} taskmd \
      ${lib.getExe' coreutils "env"} TASKMD_UI_HIDE_CMD=${lib.getExe tmux-popup-session.hide} \
      ${lib.getExe taskmd-ui}
  '';
}
