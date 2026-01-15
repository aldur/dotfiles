{
  writeShellApplication,
  fzf,
  procps,
}:

writeShellApplication {
  name = "fps";

  runtimeInputs = [
    fzf
    procps
  ];

  text = ''
    ps -eo pid,user,%cpu,%mem,comm | fzf --header-lines=1 --bind 'ctrl-k:execute(kill {1})+abort,enter:become(echo {1})'
  '';
}
