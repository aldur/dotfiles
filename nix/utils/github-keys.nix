{
  fetchurl,
  lib,
  username ? "aldur",
  sha256 ? "1wdq6qf3z27lrzcgggs2fl075l8k92kfzsp86dyzgarlz2a6r8dr",
}:

let
  # Fetch the keys file from GitHub
  keysFile = fetchurl {
    url = "https://github.com/${username}.keys";
    inherit sha256;
  };

  # Read the file content and split into lines
  keysContent = builtins.readFile keysFile;

  # Split by newlines and filter out empty lines
  keysList = builtins.filter (line: line != "") (lib.splitString "\n" keysContent);
in
keysList
