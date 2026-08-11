# The local counterpart of .github/workflows/update-pinned-packages.yml.
{ pkgs }:

{
  type = "app";
  program = pkgs.lib.getExe (
    pkgs.writeShellApplication {
      name = "update-pins";
      runtimeInputs = [ pkgs.jq ];
      text = builtins.readFile ./update-pins.sh;
    }
  );
}
