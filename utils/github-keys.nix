{
  username ? "aldur",
  sha256 ? "sha256-NIeF0Y/UzSA3mgy8geh6XOrsckgqWvwAvuclZihhEK4=",
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
