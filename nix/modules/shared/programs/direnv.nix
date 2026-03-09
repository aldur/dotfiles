# Shared direnv TOML settings.
# Consumed by home-manager (programs.direnv.config) and NixOS (programs.direnv.settings).
#
# Both levels need these because NixOS's programs.direnv sets
# DIRENV_CONFIG=/etc/direnv, which makes direnv ignore home-manager's
# ~/.config/direnv/direnv.toml.  See https://github.com/direnv/direnv/issues/1418
{
  global = {
    hide_env_diff = true;
    strict_env = true;
    disable_stdin = true;
    # https://esham.io/2023/10/direnv
    log_format = "\u001B[2mdirenv: %s\u001B[0m";
  };
}
