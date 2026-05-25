{ pkgs }:
pkgs.stdenv.mkDerivation {
  name = "count-tokens-0.1";
  nativeBuildInputs = [
    pkgs.python3Packages.wrapPython
  ];
  propagatedBuildInputs = [
    (pkgs.python312.withPackages (ps: with ps; [ tiktoken ]))
  ];
  src = pkgs.fetchurl {
    url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
    hash = "sha256-RGqVOMtsNI41FhINfAiwn1fDZJXirP/+WaW/iwz7Gi0=";
  };
  dontUnpack = true;
  buildPhase = ''
    # This is just the base64 of the URL.
    install -Dm755 $src $out/lib/data_gym/fb374d419588a4632f3f557e76b4b70aebbca790
    install -Dm755 ${./count_tokens.py} $out/bin/count-tokens

    wrapProgram $out/bin/count-tokens \
    --set DATA_GYM_CACHE_DIR $out/lib/data_gym
  '';
}
