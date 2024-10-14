{ fetchzip, stdenv }:
{
  age-plugin-se = stdenv.mkDerivation rec {
    pname = "age-plugin-se";
    version = "v0.1.4";

    src = fetchzip {
      url = "https://github.com/remko/${pname}/releases/download/${version}/${pname}-${version}-macos.zip";
      hash = "sha256-xJ4KHEpDFNGYPUsMlxoVPZe9t8raX0Ohf8jZI+z97y0=";
    };

    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      ln -vsfT $src/age-plugin-se $out/bin/age-plugin-se

      runHook postInstall
    '';
  };
}
