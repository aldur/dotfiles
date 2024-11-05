{ fetchzip, stdenv }:
{
  clarinet = stdenv.mkDerivation rec {
    pname = "clarinet";
    version = "v2.11.2";

    src = fetchzip {
      # FIXME: This only works on macOS / arm64
      # https://github.com/hirosystems/clarinet/releases/download/v2.11.2/clarinet-darwin-arm64.tar.gz
      url = "https://github.com/hirosystems/${pname}/releases/download/${version}/${pname}-darwin-arm64.tar.gz";
      hash = "sha256-fG3oKBt780NAI5wNh49lO7YumbRYigBHtRVAjaIfKUc=";
    };

    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall

      if [[ "$(uname)" != "Darwin" ]] || [[ "$(uname -m)" != "arm64" ]]; then
        echo "This derivation only implements downloads for macOS with an arm64 architecture."
        exit 1
      fi

      install -Dm755 $src/clarinet $out/bin/clarinet

      runHook postInstall
    '';
  };
}
