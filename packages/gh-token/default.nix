{
  lib,
  writeShellApplication,
  python3,
  age,
  ageCommand ? "${age}/bin/age",
  identitiesFile ? null,
  recipientsFile ? null,
}:
let
  python = python3.withPackages (ps: [ ps.requests ]);
in
writeShellApplication {
  name = "gh-token";
  text = ''
    export GH_TOKEN_AGE=${lib.escapeShellArg ageCommand}
    ${lib.optionalString (identitiesFile != null) ''
      export GH_TOKEN_IDENTITIES_FILE=${lib.escapeShellArg (toString identitiesFile)}
    ''}
    ${lib.optionalString (recipientsFile != null) ''
      export GH_TOKEN_RECIPIENTS_FILE=${lib.escapeShellArg (toString recipientsFile)}
    ''}
    exec ${python}/bin/python3 ${./gh_token.py} "$@"
  '';
  meta = {
    description = "Read and refresh age-encrypted GitHub credentials";
    mainProgram = "gh-token";
    platforms = lib.platforms.unix;
  };
}
