{
  symlinkJoin,
  makeWrapper,
  writeTextFile,
  markdownlint-cli2-unwrapped,
}:
let
  # Configuration for markdownlint
  config = {
    config = {
      MD033 = false; # Allow inline HTML
      MD034 = false; # Allow bare URLs
    };
  };

  # Write config as JSON with the expected filename pattern
  markdownlintConfig = writeTextFile {
    name = "markdownlint-config";
    destination = "/.markdownlint-cli2.jsonc";
    text = builtins.toJSON config;
  };
in
symlinkJoin {
  inherit (markdownlint-cli2-unwrapped) name;
  paths = [ markdownlint-cli2-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/markdownlint-cli2 \
      --add-flags "--config ${markdownlintConfig}/.markdownlint-cli2.jsonc"
  '';
}
