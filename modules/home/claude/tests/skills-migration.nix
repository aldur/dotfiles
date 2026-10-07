# Switch real Home Manager generations in a VM: from the two older skills
# layouts to the per-skill links. After each switch, ~/.claude/skills must be
# a real directory that keeps the skills that the user adds.
{
  pkgs,
  lib,
  self,
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  home =
    username: modules:
    self.lib.mkHome {
      inherit system username;
      profile = "headless";
      modules = [
        {
          programs.aldur = {
            lazyvim.enable = false;
            claude-code.enable = true;
          };
        }
      ]
      ++ modules;
    };
  generation = username: modules: (home username modules).activationPackage;

  # Before d907c42b: one link from ~/.claude/skills into the store.
  storeLink = {
    programs.aldur.claude-code.skills = [ ];
    home.file.".claude/skills".source = "${pkgs.claude-skills}/skills";
  };
  # From d907c42b: one link for each file of all the upstream skills.
  allFiles = {
    programs.aldur.claude-code.skills = [ ];
    home.file.".claude/skills" = {
      source = "${pkgs.claude-skills}/skills";
      recursive = true;
    };
  };
  fewer.programs.aldur.claude-code.skills = [ "pdf" ];
  none.programs.aldur.claude-code.skills = [ ];

  users = {
    storelink = {
      old = generation "storelink" [ storeLink ];
      new = generation "storelink" [ ];
      fewer = generation "storelink" [ fewer ];
    };
    allfiles = {
      old = generation "allfiles" [ allFiles ];
      new = generation "allfiles" [ ];
      none = generation "allfiles" [ none ];
    };
  };
  generations = lib.concatMap lib.attrValues (lib.attrValues users);

  defaultSkills =
    lib.sort lib.lessThan
      (home "storelink" [ ]).config.programs.aldur.claude-code.skills;
in
pkgs.testers.runNixOSTest {
  name = "claude-skills-migration";

  nodes.machine = {
    users.users = lib.genAttrs (lib.attrNames users) (_: {
      isNormalUser = true;
    });
    # Home Manager installs each generation into the user's Nix profile.
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    virtualisation = {
      additionalPaths = generations;
      memorySize = 2048;
    };
  };

  testScript = ''
    import shlex

    skills_dir = ".claude/skills"
    default_skills = ${builtins.toJSON defaultSkills}


    def run(user, command):
        return machine.succeed(f"su - {user} -c {shlex.quote(command)}")


    def activate(user, generation):
        run(user, f"{generation}/activate")


    def skills(user):
        return sorted(run(user, f"ls -A {skills_dir}").split())


    def assert_real_dir(user):
        run(user, f"test -d {skills_dir} && test ! -L {skills_dir}")


    def add_own_skill(user):
        run(user, f"mkdir {skills_dir}/mine && echo mine > {skills_dir}/mine/SKILL.md")


    def assert_own_skill(user):
        assert run(user, f"cat {skills_dir}/mine/SKILL.md").strip() == "mine"
        run(user, f"test ! -L {skills_dir}/mine/SKILL.md")


    machine.wait_for_unit("multi-user.target")

    with subtest("old store link: the switch replaces it with a directory"):
        activate("storelink", "${users.storelink.old}")
        run("storelink", f"test -L {skills_dir}")
        run("storelink", f"! mkdir {skills_dir}/mine")
        activate("storelink", "${users.storelink.new}")
        assert_real_dir("storelink")
        assert skills("storelink") == default_skills, skills("storelink")
        run("storelink", f"test -L {skills_dir}/pdf/SKILL.md")

    with subtest("old store link: own skills survive later switches"):
        add_own_skill("storelink")
        activate("storelink", "${users.storelink.new}")
        assert_own_skill("storelink")
        activate("storelink", "${users.storelink.fewer}")
        assert_real_dir("storelink")
        assert skills("storelink") == ["mine", "pdf"], skills("storelink")
        assert_own_skill("storelink")

    with subtest("all upstream files: the switch removes the extra skills"):
        activate("allfiles", "${users.allfiles.old}")
        assert_real_dir("allfiles")
        assert "canvas-design" in skills("allfiles")
        add_own_skill("allfiles")
        activate("allfiles", "${users.allfiles.new}")
        assert_real_dir("allfiles")
        assert skills("allfiles") == sorted(default_skills + ["mine"]), skills("allfiles")
        assert_own_skill("allfiles")

    with subtest("no Nix skills: the directory stays for the watcher"):
        run("allfiles", f"rm -r {skills_dir}/mine")
        activate("allfiles", "${users.allfiles.none}")
        assert_real_dir("allfiles")
        assert skills("allfiles") == [], skills("allfiles")
  '';
}
