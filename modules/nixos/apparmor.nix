# Load AppArmor policies. A policy runs in complain mode until its name is
# in aldur.apparmor.enforce, so a new profile only logs at first.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.aldur.apparmor;
  inherit (lib) mkOption types;
in
{
  options.aldur.apparmor = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable the AppArmor LSM and load the policies below. The LSM list
        is a kernel parameter, so the change needs a reboot. A host with a
        foreign kernel cannot add the LSM.
      '';
    };
    policies = mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = ''
        AppArmor policy text by name. One policy can hold more than one
        profile. Every policy starts in complain mode.
      '';
    };
    enforce = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "agent-sandbox" ];
      description = ''
        Names of policies to enforce. The other policies only log the
        rules they would deny. Read them with `journalctl -k --grep=apparmor`.
        Roll out one policy at a time: load it, read the log for a few
        days, fix the policy, then add its name here.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = lib.all (name: cfg.policies ? ${name}) cfg.enforce;
        message = "aldur.apparmor.enforce names a policy that aldur.apparmor.policies does not define.";
      }
      {
        assertion = cfg.enable -> !(config.hardening.foreignKernel or false);
        message = "aldur.apparmor.enable needs the NixOS kernel. This host sets hardening.foreignKernel.";
      }
    ];

    # podman treats AppArmor as absent unless apparmor_parser is on PATH.
    environment.systemPackages = lib.mkIf cfg.enable [ pkgs.apparmor-parser ];

    security.apparmor = lib.mkIf cfg.enable {
      enable = true;
      policies = lib.mapAttrs (name: profile: {
        inherit profile;
        state = if lib.elem name cfg.enforce then "enforce" else "complain";
      }) cfg.policies;
    };
  };
}
