{
  lib,
  writeText,
  self,
  system,
}:

let
  installsAgentLog =
    extra:
    let
      home = self.lib.mkHome {
        inherit system;
        modules = [ extra ];
      };
    in
    lib.any (package: (package.pname or package.name or "") == "agent-log") home.config.home.packages;

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
      name = "llm alone, which is not an agent";
      wanted = false;
      module.programs.llm.enable = true;
    }
    {
      name = "pi";
      wanted = true;
      module.programs.pi.enable = true;
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
