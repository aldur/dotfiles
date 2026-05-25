let
  pkgs = import <nixpkgs> {};
  gpg-encrypt = pkgs.callPackage ./gpg-encrypt.nix {};
in
{
  inherit gpg-encrypt;

  # Integration test - can be run with: nix-build -A tests
  tests = pkgs.callPackage ./test.nix {
    inherit gpg-encrypt;
  };

  # Default output is the package itself
  default = gpg-encrypt;
}
