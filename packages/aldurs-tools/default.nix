{
  writeShellApplication,
  fzf,
  lib,
  tools,
}:
let
  names = lib.unique (map (t: t.pname or t.name) tools);
  nameArgs = lib.concatMapStringsSep " " lib.escapeShellArg names;
in
writeShellApplication {
  name = "aldurs-tools";
  runtimeInputs = [ fzf ] ++ tools;
  text = ''
    printf '%s\n' ${nameArgs} \
      | fzf --prompt='tool> ' \
            --height=40% \
            --reverse \
            --with-shell 'bash -c' \
            --preview '(timeout 2 {} --help </dev/null 2>&1 || echo "(no help available)") | head -60' \
            --preview-window=right,60%,wrap \
            --bind 'enter:become(echo {})'
  '';
}
