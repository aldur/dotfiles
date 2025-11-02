{
  totp-cli,
  symlinkJoin,
  makeWrapper,
}:
symlinkJoin {
  inherit (totp-cli) name;
  paths = [ totp-cli ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/totp-cli \
      --set TOTP_CLI_CREDENTIAL_FILE /dev/null
  '';
}
