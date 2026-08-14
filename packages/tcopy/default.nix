{
  writeArgcApplication,
  coreutils,
}:

writeArgcApplication {
  name = "tcopy";
  file = ./tcopy.sh;
  runtimeInputs = [ coreutils ];
}
