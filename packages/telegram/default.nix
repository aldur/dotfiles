{
  writeShellApplication,
  curl,
}:

writeShellApplication {
  name = "telegram";
  runtimeInputs = [ curl ];
  text = builtins.readFile ./telegram.sh;
}
