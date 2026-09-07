{
  lib,
  writeText,
  self,
  inputs,
  system,
}:
let
  evaluate =
    extra:
    let
      evaluated = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs.inputs = inputs // {
          inherit self;
        };
        modules = [
          self.nixosModules.default
          (
            { modulesPath, ... }:
            {
              imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
              networking.hostName = "sandbox-check";
              users.allowNoPasswordLogin = true;
            }
          )
          extra
        ];
      };
    in
    evaluated.config.home-manager.users.${evaluated.config.mainUser};

  cases = [
    {
      codex = false;
      claude = false;
      sandbox = true;
    }
    {
      codex = true;
      claude = false;
      sandbox = true;
    }
    {
      codex = false;
      claude = true;
      sandbox = true;
    }
    {
      codex = true;
      claude = true;
      sandbox = true;
    }
    {
      codex = true;
      claude = true;
      sandbox = false;
    }
  ];
  check =
    case:
    let
      home = evaluate {
        programs.aldur = {
          codex = {
            enable = case.codex;
            sandbox.enable = case.sandbox;
          };
          claude-code = {
            enable = case.claude;
            sandbox.enable = case.sandbox;
          };
        };
      };
      packages = builtins.filter (
        package: (package.pname or package.name or "") == "agent-sandbox"
      ) home.home.packages;
      aliases = home.home.shellAliases;
      prefix = lib.getExe home.programs.agent-sandbox.package;
    in
    builtins.length packages == 1
    && (aliases ? codex-yolo) == case.codex
    && (aliases ? claude-yolo) == case.claude
    && (
      !case.codex
      ||
        aliases.codex-yolo == (
          lib.optionalString case.sandbox "${prefix} --profile codex -- "
          + "codex --dangerously-bypass-approvals-and-sandbox"
        )
    )
    && (
      !case.claude
      || (
        lib.hasSuffix (
          lib.optionalString case.sandbox "${prefix} --profile claude -- "
          + "claude --dangerously-skip-permissions"
        ) aliases.claude-yolo
        && lib.hasInfix " --profile claude -- " aliases.claude-yolo == case.sandbox
      )
    );
in
assert lib.assertMsg (lib.all check cases)
  "agent-sandbox package or -yolo alias integration failed";
writeText "agent-sandbox-modules" ''
  One shared command is installed with no agents, either agent, or both agents.
  Enabled -yolo aliases supply their profiles, commands and flags automatically.
  Disabling sandbox wrapping retains direct agent commands.
''
