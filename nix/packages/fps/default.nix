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
    ps -eo pid,user,%cpu,%mem,args | fzf --header-lines=1 --footer "<c-k> kills PID; <cr> prints PID" --bind 'ctrl-k:execute(kill {1})+abort,enter:become(echo {1})'
  '';
}
