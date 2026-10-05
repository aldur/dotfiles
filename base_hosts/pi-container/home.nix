{
  pkgs,
  lib,
  baseHome,
  lazyvim-light,
  lazyvim-bin,
  dotfiles,
  runtimePython,
  config,
  ...
}:
let
  base = import "${dotfiles}/modules/shared/environment.nix" { inherit pkgs lib; };
  agentSandbox =
    import "${dotfiles}/modules/home/agent-sandbox/package.nix"
      {
        inherit lib;
        pkgs = pkgs // {
          python3 = runtimePython;
        };
      }
      {
        enableDbus = false;
        # NOTE: Fine here, a container has no other running process usually.
        dangerouslyInheritProc = true;
        profiles.pi = {
          allowNixDaemon = false;
          readOnlyPaths = [
            "/bin"
            "/usr/bin"
            "~/.config"
          ];
          agentReadWritePaths = [ "~/.pi/agent" ];
          extraEnvironmentAllowlist = [ "LLAMA_BASE_URL" ];
        };
      };
  pi-yolo =
    import "${dotfiles}/modules/home/yolo-script.nix"
      {
        inherit pkgs lib;
        config.programs.agent-sandbox.package = agentSandbox;
      }
      {
        agent = "pi";
        describe = "Run Pi in the sandbox with read-only Git metadata";
        sandbox = true;
        text = ''
          exec "''${sandbox[@]}" pi "$@"
        '';
      };
in
{
  imports = [
    "${dotfiles}/modules/home/home.nix"
    { options.home.packages = lib.mkOption { apply = map lib.getBin; }; }
  ];
  identity = { inherit (baseHome.identity) githubUser email; };
  home = {
    inherit (baseHome.home) username homeDirectory stateVersion;
    extraOutputsToInstall = lib.mkForce [ ];
    packages =
      (map (p: if lib.getName p == "python3" then runtimePython else p) base.cli)
      ++ base.terminfo
      ++ (with pkgs; [
        pi-yolo
        lazyvim-light
        tcopy
        tmux-palette
        (lazyvim-popup.override { inherit lazyvim-bin; })
        (lazygit-popup.override {
          lazygit = config.programs.lazygit.package;
          inherit (config.programs.lazygit) settings;
        })
      ]);
    # Use the C.UTF-8 locale from glibc. Do not include the other locales.
    sessionVariables.LOCALE_ARCHIVE_2_27 = lib.mkForce "";
    sessionVariables.EDITOR = "lazyvim";
    sessionVariables.VISUAL = "lazyvim";
  };
  manual.manpages.enable = false;
  programs.man.enable = false;
  xdg.mime.enable = false;
  systemd.user.enable = false;
  programs.pi.enable = true;
  programs.git.signing.format = null;
  programs.fish.generateCompletions = false;
  programs.direnv.nix-direnv.enable = lib.mkForce false;
}
