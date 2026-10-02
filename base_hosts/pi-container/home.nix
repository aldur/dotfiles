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
