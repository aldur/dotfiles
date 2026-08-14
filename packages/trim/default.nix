{
  writeArgcApplication,
  gnused,
}:

writeArgcApplication {
  name = "trim";
  file = ./trim.sh;
  runtimeInputs = [ gnused ];
}
