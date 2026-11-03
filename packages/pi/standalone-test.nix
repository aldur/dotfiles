{ pkgs, pi }:
pkgs.runCommand "pi-standalone-test" { } ''
  export HOME="$TMPDIR/home"
  export PI_CODING_AGENT_DIR="$HOME/agent"
  export PNPM_HOME="$HOME/pnpm"
  mkdir -p "$PI_CODING_AGENT_DIR/skills/writing-well"
  printf 'local instructions' > "$PI_CODING_AGENT_DIR/AGENTS.md"
  printf 'local skill' > "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md"

  ${pkgs.lib.getExe pi} --version
  backup=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backup[@]}" = 1
  test "$(cat "''${backup[0]}/AGENTS.md")" = 'local instructions'
  test "$(cat "''${backup[0]}/skills/writing-well/SKILL.md")" = 'local skill'
  cmp "$PI_CODING_AGENT_DIR/AGENTS.md" ${../../modules/home/agents/AGENTS.md}
  cmp "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md" ${../../skills/writing-well/SKILL.md}

  ${pkgs.lib.getExe pi} --version
  backups=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backups[@]}" = 1

  rm "$PI_CODING_AGENT_DIR/skills/writing-well"
  ln -s /old/skill "$PI_CODING_AGENT_DIR/skills/writing-well"
  ${pkgs.lib.getExe pi} --version
  cmp "$PI_CODING_AGENT_DIR/skills/writing-well/SKILL.md" ${../../skills/writing-well/SKILL.md}
  backups=("$PI_CODING_AGENT_DIR"/.dotfiles-backup.*)
  test "''${#backups[@]}" = 2
  touch "$out"
''
