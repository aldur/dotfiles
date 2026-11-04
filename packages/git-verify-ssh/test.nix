{ runCommand, git-verify-ssh, git, openssh, gnupg, githubVerifier }:

runCommand "git-verify-ssh-test" {
  nativeBuildInputs = [ git-verify-ssh git openssh gnupg ];
  GITHUB_VERIFIER = githubVerifier;
  GITHUB_COMMIT = ./github-commit.txt;
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  bash ${./test.sh}
  touch "$out"
''
