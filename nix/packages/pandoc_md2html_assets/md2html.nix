{ stdenv }:
stdenv.mkDerivation rec {
  pname = "pandoc_md2html_assets";
  version = "v0.0.1";

  src = builtins.path {
    path = ./assets;
    name = "pandoc_md2html_assets";
  };

  phases = [ "installPhase" ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/assets
    cp -r ${src}/* $out/assets

    runHook postInstall
  '';
}
