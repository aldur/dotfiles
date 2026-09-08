# The SSH public keys of a GitHub account, as a list of strings.
# Only `builtins`, to stay independent of nixpkgs and the system.
{
  username ? "aldur",
  # The SRI hash of `https://github.com/<username>.keys`. For another
  # account, or after a key change, Nix reports the new hash in the
  # mismatch error; copy it from there.
  sha256 ? if username == "aldur" then "sha256-NIeF0Y/UzSA3mgy8geh6XOrsckgqWvwAvuclZihhEK4=" else "",
}:
let
  keysFile = builtins.fetchurl {
    url = "https://github.com/${username}.keys";
    inherit sha256;
  };

  keysContent = builtins.readFile keysFile;
in
builtins.filter (line: line != "" && line != [ ]) (builtins.split "\n" keysContent)
