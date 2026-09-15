# Forward every shared option, so adding one cannot silently omit a platform.
{
  osConfig,
  stateVersion,
  pkgs,
  lib,
  ...
}:
let
  declarations =
    (import ../shared/options.nix {
      config = osConfig;
      inherit pkgs lib;
    }).options;
  # Filter read-only declarations before producing definitions: even an empty
  # mkIf definition would count as a second value for a read-only option.
  forward =
    path: options:
    lib.mapAttrs (
      name: option:
      let
        optionPath = path ++ [ name ];
      in
      if lib.isOption option then
        lib.mkDefault (lib.getAttrFromPath optionPath osConfig)
      else
        forward optionPath option
    ) (lib.filterAttrs (_: option: !(lib.isOption option && (option.readOnly or false))) options);
  inherited = forward [ ] declarations;

in
inherited
// {
  home = {
    inherit stateVersion;
    username = lib.mkDefault osConfig.mainUser;
  };
}
