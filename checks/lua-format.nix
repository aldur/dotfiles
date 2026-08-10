{
  lib,
  runCommand,
  stylua,
}:

# Fails if the repo's own lua is not stylua-formatted.
#
# The editor ships stylua as a formatter for the user (packages/lazyvim/
# runtime.nix), but nothing checked the lua in this repo, so files arrived with
# spaces while the rest of the tree used tabs. stylua's defaults already match
# the tree, so there is no configuration file to keep in step.
#
# The source filter keeps the derivation off unrelated edits: only lua files,
# and only from the directories that hold the repo's own.
let
  sources = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.intersection (lib.fileset.unions [
      ../packages/lazyvim
      ../checks
    ]) (lib.fileset.fileFilter (file: file.hasExt "lua") ../.);
  };
in
runCommand "lua-format"
  {
    nativeBuildInputs = [ stylua ];
  }
  ''
    cd ${sources}
    if ! stylua --check .; then
      echo
      echo "lua is not formatted; run: stylua packages/lazyvim checks"
      exit 1
    fi
    touch $out
  ''
