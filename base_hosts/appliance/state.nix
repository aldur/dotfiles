{ config, inputs, lib, ... }:
let
  cfg = config.aldur.appliance.state;
in
{
  imports = [ inputs.preservation.nixosModules.preservation ];

  options.aldur.appliance.state.directories = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Directories relative to the user's home to preserve under /state.";
  };

  config.preservation = {
    enable = true;
    preserveAt."/state".users.${config.mainUser}.directories =
      map (d: { directory = d; mode = "0700"; }) cfg.directories;
  };
}
