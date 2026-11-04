{ writeShellApplication, git, openssh, coreutils, callPackage }:

writeShellApplication {
  name = "git-verify-ssh";
  runtimeInputs = [ git openssh coreutils ];
  text = builtins.readFile ./git-verify-ssh.sh;
  passthru.tests.integration = callPackage ./test.nix { };
}
