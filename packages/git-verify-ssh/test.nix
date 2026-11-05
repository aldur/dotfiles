{ runCommand, git-verify-ssh, git, openssh, gnupg }:

runCommand "git-verify-ssh-test" {
  nativeBuildInputs = [ git-verify-ssh git openssh gnupg ];
  GITHUB_REPOSITORY = ./github-root.bundle;
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  bash ${./test.sh}
  touch "$out"
''
