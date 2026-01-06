{
  writeShellApplication,
  ghostscript,
}:

writeShellApplication {
  name = "flatten-pdf";

  runtimeInputs = [
    ghostscript
  ];

  text = builtins.readFile ./flatten-pdf.sh;
}
