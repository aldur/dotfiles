{
  lib,
  writeText,
  # This flake, for the NixOS modules it exports, and the inputs those modules
  # are given as `specialArgs`.
  self,
  inputs,
  system,
}:

# agent-log reads Claude Code, pi and Codex transcripts, so it is installed as
# soon as any of the three is enabled and left out when none is. The gate spans
# two levels — two system options and one home-manager option — which is easy
# to get subtly wrong and impossible to notice, since the failure is a missing
# command rather than a broken build.

let
  evaluate =
    extra:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inputs = inputs // {
          inherit self;
        };
      };
      modules = [
        self.nixosModules.default
        (
          { modulesPath, ... }:
          {
            imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
            networking.hostName = "gating";
            users.allowNoPasswordLogin = true;
          }
        )
        extra
      ];
    };

  installsAgentLog =
    extra:
    let
      evaluated = evaluate extra;
      user = evaluated.config.mainUser;
      packages = evaluated.config.home-manager.users.${user}.home.packages;
    in
    lib.any (package: (package.pname or package.name or "") == "agent-log") packages;

  cases = [
    {
      name = "no agent enabled";
      wanted = false;
      module = { };
    }
    {
      name = "claude-code";
      wanted = true;
      module = {
        programs.aldur.claude-code.enable = true;
      };
    }
    {
      name = "codex";
      wanted = true;
      module = {
        programs.aldur.codex.enable = true;
      };
    }
    {
      name = "pi, via the home-manager option";
      wanted = true;
      module =
        { config, ... }:
        {
          home-manager.users.${config.mainUser}.programs.llm.enable = true;
        };
    }
  ];

  failures = lib.filter (case: installsAgentLog case.module != case.wanted) cases;
in

assert lib.assertMsg (failures == [ ]) (
  "agent-log gating is wrong for: " + lib.concatMapStringsSep ", " (case: case.name) failures
);

writeText "agent-log-gating" ''
  agent-log is installed for: ${
    lib.concatMapStringsSep ", " (case: case.name) (lib.filter (case: case.wanted) cases)
  }
  and left out when none of them is enabled.
''
