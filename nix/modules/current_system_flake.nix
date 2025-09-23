{
  inputs,
  ...
}:
{
  # Drop a link to the current system configuration flake in to /etc.
  # That way we can tell what configuration built the current
  # system version.
  # NOTE: This will cause a rebuild for any change in the `flake` directory,
  # even if it's just refactoring that wouldn't cause a rebuild.
  # https://discourse.nixos.org/t/nixos-config-flake-store-path-for-run-current-system/24812/6
  environment.etc."current-system-flake".source = inputs.self;

  # Add it also to the user's home
  home-manager.users.aldur.home.file."current-system-flake".source = inputs.self;
}
