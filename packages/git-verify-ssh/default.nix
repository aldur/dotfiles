{
  writeShellApplication,
  writeShellScript,
  git,
  openssh,
  coreutils,
  callPackage,
  fetchurl,
  runCommand,
  gnupg,
  emptyDirectory,
}:
let
  githubKeys = fetchurl {
    url = "https://github.com/web-flow.gpg";
    hash = "sha256-bor2h/YM8/QDFRyPsbJuleb55CTKYMyPN4e9RGaj74Q=";
  };
  githubKeyring = runCommand "github-signing-keyring.gpg" { } ''
    ${gnupg}/bin/gpg --batch --dearmor --output "$out" ${githubKeys}
  '';
  githubVerifier = writeShellScript "verify-github-signature" ''
    exec ${gnupg}/bin/gpg --no-options --homedir ${emptyDirectory} \
      --batch --no-default-keyring --keyring ${githubKeyring} \
      --trust-model always --no-auto-key-retrieve --lock-never --no-permission-warning "$@"
  '';
in

writeShellApplication {
  name = "git-verify-ssh";
  runtimeInputs = [ git openssh coreutils ];
  text = ''
    github_verifier=${githubVerifier}
  '' + builtins.readFile ./git-verify-ssh.sh;
  passthru.tests.integration = callPackage ./test.nix { inherit githubVerifier; };
}
