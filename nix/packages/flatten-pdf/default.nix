{
  writeArgcApplication,
  ghostscript,
}:

writeArgcApplication {
  name = "flatten-pdf";
  file = ./flatten-pdf.sh;
  runtimeInputs = [ ghostscript ];
}
