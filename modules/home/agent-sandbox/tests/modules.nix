{
  lib,
  runCommand,
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

  # Each agent has a `<agent>-yolo` script with a fixed launch line. The
  # flag turns off the agent's own sandbox and approvals; the profile
  # prefix wraps the process in the agent sandbox.
  agents = {
    codex = {
      enabled = case: case.codex;
      launch = "codex --dangerously-bypass-approvals-and-sandbox";
    };
    claude = {
      enabled = case: case.claude;
      launch = "claude --dangerously-skip-permissions";
    };
  };

  homes = map (
    case:
    evaluate {
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
    }
  ) cases;

  findPackage =
    name: home:
    lib.findFirst (package: (package.pname or package.name or "") == name) null home.home.packages;

  # Evaluation-time: one agent-sandbox package, and a -yolo script for each
  # enabled agent, with no -yolo alias left behind.
  check =
    case: home:
    builtins.length (
      builtins.filter (
        package: (package.pname or package.name or "") == "agent-sandbox"
      ) home.home.packages
    ) == 1
    && lib.all (
      name:
      (findPackage "${name}-yolo" home != null) == agents.${name}.enabled case
      && !(home.home.shellAliases ? "${name}-yolo")
    ) (lib.attrNames agents);

  # Build-time: the sandbox prefix is only visible in the built script.
  scriptChecks = lib.concatStrings (
    lib.zipListsWith (
      case: home:
      lib.concatStrings (
        lib.mapAttrsToList (
          name: agent:
          lib.optionalString (agent.enabled case) (
            let
              script = lib.getExe (findPackage "${name}-yolo" home);
              prefix = lib.getExe home.programs.agent-sandbox.package;
              launch = ''exec ${lib.optionalString case.sandbox "${prefix} --profile ${name} -- "}${agent.launch} "$@"'';
            in
            ''
              grep -Fxq ${lib.escapeShellArg launch} ${script}
              ${lib.optionalString (!case.sandbox) "! grep -Fq ' --profile ${name} ' ${script}"}
            ''
          )
        ) agents
      )
    ) cases homes
  );
in
assert lib.assertMsg (lib.all lib.id (
  lib.zipListsWith check cases homes
)) "agent-sandbox package or -yolo script integration failed";
runCommand "agent-sandbox-modules" { } ''
  ${scriptChecks}
  cat > $out <<EOF
  One shared command is installed with no agents, either agent, or both agents.
  The -yolo script of each enabled agent supplies its profile, command and
  flags. Disabling sandbox wrapping retains direct agent commands.
  EOF
''
