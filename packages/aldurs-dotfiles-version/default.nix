# Prints the aldur-dotfiles revision this system was built from.
# `self` metadata is baked in at eval time, so the output always matches
# the flake revision of the running configuration.
{
  lib,
  writeShellApplication,
  self,
}:

let
  inherit (lib) substring optionalString;

  rev = self.rev or self.dirtyRev or "unknown";
  shortRev = self.shortRev or self.dirtyShortRev or "unknown";

  # "YYYYMMDDHHMMSS" -> "YYYY-MM-DD HH:MM:SS UTC"
  lmd = self.lastModifiedDate or null;
  lastModified =
    if lmd == null then
      "unknown"
    else
      "${substring 0 4 lmd}-${substring 4 2 lmd}-${substring 6 2 lmd}"
      + " ${substring 8 2 lmd}:${substring 10 2 lmd}:${substring 12 2 lmd} UTC";
in
writeShellApplication {
  name = "aldurs-dotfiles-version";
  text = ''
    echo "aldurs-dotfiles ${shortRev}"
    echo "commit:        ${rev}"
    echo "last modified: ${lastModified}"
    echo "narHash:       ${self.narHash or "unknown"}"
    echo "nixpkgs:       ${self.inputs.nixpkgs.shortRev or "unknown"}"
    ${optionalString (self ? rev) ''
      echo "url:           https://github.com/aldur/dotfiles/commit/${rev}"
    ''}
  '';
}
