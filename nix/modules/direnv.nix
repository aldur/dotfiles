{ ... }: {
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  environment.variables = {
    # https://esham.io/2023/10/direnv
    DIRENV_LOG_FORMAT = ''$(printf "\033[2mdirenv: %%s\033[0m")'';
  };

  # https://github.com/direnv/direnv/issues/1418
  home-manager.users.aldur = { ... }: {
    home.file.".config/direnv/direnvrc".text = "";
  };
}
