{
  writeArgcApplication,
  coreutils,
}:

writeArgcApplication {
  name = "nospace";
  file = ./nospace.sh;
  runtimeInputs = [ coreutils ];
}
