{
  writeArgcApplication,
  ghostscript,
  coreutils,
}:

writeArgcApplication {
  name = "flatten-pdf";
  file = ./flatten-pdf.sh;
  runtimeInputs = [ ghostscript coreutils ];
}
