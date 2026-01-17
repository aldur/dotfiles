{
  writeShellApplication,
  stdenv,
  installShellFiles,
  ghostscript,
  argc,
}:

let
  name = "flatten-pdf";
  shellApp = writeShellApplication {
    inherit name;

    runtimeInputs = [
      argc
      ghostscript
    ];

    text = builtins.readFile ./flatten-pdf.sh;
  };
in
stdenv.mkDerivation {
  inherit name;
  nativeBuildInputs = [ installShellFiles ];
  buildCommand = ''
    mkdir -p $out
    cp -r ${shellApp}/* $out/

    installShellCompletion --cmd ${name} \
      --bash <(${argc}/bin/argc --argc-completions bash ${name} < ${./flatten-pdf.sh}) \
      --zsh <(${argc}/bin/argc --argc-completions zsh ${name} < ${./flatten-pdf.sh}) \
      --fish <(${argc}/bin/argc --argc-completions fish ${name} < ${./flatten-pdf.sh})
  '';
}
