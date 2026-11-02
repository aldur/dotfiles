{ pkgs }:
let
  inherit (pkgs) lib;
  inherit (pkgs) pi;
  skills = import ../../skills;
  config = (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ../../modules/home/pi.nix
      {
        options.home = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.anything; default = { }; };
        config.programs.pi.enable = true;
      }
    ];
  }).config.programs.pi;
  defaults = pkgs.writeText "pi-standalone-config.json" (
    builtins.toJSON { inherit (config) settings keybindings; }
  );
in
pkgs.writeShellApplication {
  name = "pi";
  passthru = { inherit (pi) plugins configSync; };
  meta = pi.meta;
  text = ''
    agent_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
    ${lib.getExe pi.configSync} ${defaults} "$agent_dir"
    mkdir -p "$agent_dir/skills"
    backup_dir=
    link_managed() {
      local source="$1" relative="$2" target="$agent_dir/$2"
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        return
      fi
      if [ -e "$target" ] || [ -L "$target" ]; then
        if [ -z "$backup_dir" ]; then
          backup_dir=$(mktemp -d "$agent_dir/.dotfiles-backup.XXXXXXXX")
        fi
        mkdir -p "$(dirname "$backup_dir/$relative")"
        mv "$target" "$backup_dir/$relative"
      fi
      ln -s "$source" "$target"
    }
    link_managed ${../../modules/home/agents/AGENTS.md} AGENTS.md
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: source: ''
      link_managed ${source} ${lib.escapeShellArg "skills/${name}"}
    '') skills)}
    exec ${lib.getExe pi} "$@"
  '';
}
