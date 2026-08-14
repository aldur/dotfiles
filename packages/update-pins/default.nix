{ writeArgcApplication, jq }:

writeArgcApplication {
  name = "update-pins";
  file = ./update-pins.sh;
  runtimeInputs = [ jq ];
  meta.description = "Run the `updatePins` bump legs of the flake in the current directory";
}
