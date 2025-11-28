{
  username ? "aldur",
  sha256 ? "1wdq6qf3z27lrzcgggs2fl075l8k92kfzsp86dyzgarlz2a6r8dr",
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
