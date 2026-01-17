# Provides writeArgcApplication, a wrapper around writeShellApplication
# that integrates argc for argument parsing and generates shell completions.
#
# Usage:
#   writeArgcApplication {
#     name = "my-script";
#     file = ./my-script.sh;  # or use `text = "..."` for inline scripts
#     runtimeInputs = [ someDep ];
#   }
#
# Script requirements:
#   - Use argc comment annotations to define arguments:
#       # @describe Script description
#       # @arg input! Required positional argument
#       # @arg output Optional positional argument
#       # @option -v --verbose Enable verbose mode
#       # @flag -f --force Force operation
#
#   - Declare argc variables before eval to satisfy shellcheck:
#       declare argc_input argc_output argc_verbose argc_force
#       eval "$(argc --argc-eval "$0" "$@")"
#
#   - argc prefixes all variables with `argc_`. Flags become `argc_<name>`
#     with value 0 or 1. Options and args become `argc_<name>` with the value.
#
# See https://github.com/sigoden/argc for full documentation.

final: prev: {
  writeArgcApplication =
    {
      name,
      text ? null,
      file ? null,
      runtimeInputs ? [ ],
      meta ? { },
    }:
    assert (text != null) != (file != null);
    let
      scriptSource = if file != null then builtins.readFile file else text;
      scriptFile = if file != null then file else prev.writeText "${name}.sh" text;

      shellApp = prev.writeShellApplication {
        inherit name meta;
        runtimeInputs = [ final.argc ] ++ runtimeInputs;
        text = scriptSource;
      };
    in
    prev.stdenv.mkDerivation {
      inherit name meta;
      nativeBuildInputs = [ prev.installShellFiles ];
      buildCommand = ''
        mkdir -p $out
        cp -r ${shellApp}/* $out/

        installShellCompletion --cmd ${name} \
          --bash <(${final.argc}/bin/argc --argc-completions bash ${name} < ${scriptFile}) \
          --zsh <(${final.argc}/bin/argc --argc-completions zsh ${name} < ${scriptFile}) \
          --fish <(${final.argc}/bin/argc --argc-completions fish ${name} < ${scriptFile})
      '';
    };
}
