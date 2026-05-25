{
  username ? "aldur",
  sha256 ? "sha256-fX18uyZHlf1Sp+RpCAUiCSP2VZf9gGdHZfqWV33b5W0=",
}:
# NOTE: This uses only `builtins` to be independent of nixpkgs/system
let
  keysFile = builtins.fetchurl {
    url = "https://github.com/${username}.keys";
    inherit sha256;
  };

  keysContent = builtins.readFile keysFile;
in
builtins.filter (line: line != "" && line != [ ]) (builtins.split "\n" keysContent)
