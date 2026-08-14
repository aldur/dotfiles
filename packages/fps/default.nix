{
  writeArgcApplication,
  fzf,
  procps,
}:

writeArgcApplication {
  name = "fps";
  file = ./fps.sh;

  runtimeInputs = [
    fzf
    procps
  ];
}
