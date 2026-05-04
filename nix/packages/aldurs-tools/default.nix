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
            --preview '({} --help 2>&1 || echo "(no --help available)") | head -60' \
            --preview-window=right,60%,wrap \
            --bind 'enter:become(echo {})'
  '';
}
