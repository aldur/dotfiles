{
  username ? "aldur",
  sha256 ? "04l39mybmk8hhggwv2gwjx1ad591hjbkf440lrk8j27i0ddq9mhx",
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
