{
  symlinkJoin,
  makeWrapper,
  writeTextFile,
  runCommand,
  python3,
  markdownlint-cli2-unwrapped,
}:
let
  # The CLI wrapper also supplies these defaults to editor integrations.
  markdownlintConfig = writeTextFile {
    name = "markdownlint-config";
    destination = "/.markdownlint-cli2.cjs";
    text = builtins.readFile ./defaults.markdownlint-cli2.cjs;
  };
  package = symlinkJoin {
    inherit (markdownlint-cli2-unwrapped) name;
    paths = [ markdownlint-cli2-unwrapped ];
    nativeBuildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/markdownlint-cli2 \
        --add-flags "--config ${markdownlintConfig}/.markdownlint-cli2.cjs"
    '';
    passthru.tests.formatting =
      runCommand "markdownlint-formatting" { nativeBuildInputs = [ python3 ]; }
        ''
          python ${./tests.py} ${package}/bin/markdownlint-cli2
          touch "$out"
        '';
  };
in
package
