{
  writeArgcApplication,
  qpdf,
}:

writeArgcApplication {
  name = "split-pdf";
  file = ./split-pdf.sh;
  runtimeInputs = [ qpdf ];
}
