{ runCommand, git-verify-ssh, git, openssh, gnupg }:

runCommand "git-verify-ssh-test" {
  nativeBuildInputs = [ git-verify-ssh git openssh gnupg ];
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  bash ${./test.sh}
  touch "$out"
''
