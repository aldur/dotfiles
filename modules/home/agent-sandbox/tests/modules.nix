{
  lib,
  pkgs,
  runCommand,
  self,
  inputs,
  system,
}:
let
  testPython = pkgs.python3.withPackages (ps: [ ps.pyte ]);
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
  # flag turns off the agent's own sandbox and approvals; the `sandbox`
  # array wraps the process in the agent sandbox when it is enabled.
  agents = {
    codex = {
      enabled = case: case.codex;
    };
    claude = {
      enabled = case: case.claude;
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

  # Execute the actual module-generated launchers. The probe agent records
  # their observable contract; the separate CLI check uses the pinned clients.
  manifest = pkgs.writeText "agent-yolo-cases.json" (
    builtins.toJSON {
      cases = lib.zipListsWith (case: home: {
        inherit (case) sandbox;
        launchers = lib.mapAttrs (name: _: lib.getExe (findPackage "${name}-yolo" home)) (
          lib.filterAttrs (_: agent: agent.enabled case) agents
        );
      }) cases homes;
      native = {
        codex = lib.getExe (findPackage "codex" (builtins.elemAt homes 3));
        claude = lib.getExe (builtins.elemAt homes 3).programs.claude-code.package;
      };
      bash = "${pkgs.bash}/bin/bash";
      python = "${testPython}/bin/python3";
      bwrap = lib.getExe pkgs.bubblewrap;
      dbus = "${pkgs.dbus}/bin/dbus-run-session";
      dbusConfig = "${pkgs.dbus}/share/dbus-1/session.conf";
      certificates = "${pkgs.cacert}/etc/ssl/certs";
      path = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.dbus
      ];
    }
  );
  runTests = mode: ''
    ${testPython}/bin/python3 ${./yolo-e2e.py} ${manifest} ${mode}
    touch "$out"
  '';

in
assert lib.assertMsg (lib.all lib.id (
  lib.zipListsWith check cases homes
)) "agent-sandbox package or -yolo script integration failed";
runCommand "agent-sandbox-modules" {
  passthru.transportManifest = manifest;
  passthru.tests.cli = runCommand "agent-yolo-cli" { } (runTests "cli");
} (runTests "wrappers")
