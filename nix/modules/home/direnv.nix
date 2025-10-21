{ ... }: {
  home.sessionVariables = {
    # https://esham.io/2023/10/direnv
    DIRENV_LOG_FORMAT = ''$(printf "\033[2mdirenv: %%s\033[0m")'';
  };

  # https://github.com/direnv/direnv/issues/1418
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    config = {
      # https://direnv.net/man/direnv.toml.1.html#global
      global = {
        hide_env_diff = true;
        strict_env = true;
        disable_stdin = true;
      };
    };
  };
}
