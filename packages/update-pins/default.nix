{ writeShellApplication, jq }:

writeShellApplication {
  name = "update-pins";
  runtimeInputs = [ jq ];
  text = builtins.readFile ./update-pins.sh;
  meta.description = "Run the `updatePins` bump legs of the flake in the current directory";
}
