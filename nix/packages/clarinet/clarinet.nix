{
  fetchzip,
  stdenv,
  system,
}:
{
  clarinet = stdenv.mkDerivation rec {
    pname = "clarinet";
    version = "v2.11.2";

    src =
      let
        architecture_and_hash =
          {
            aarch64-darwin = [
              "darwin-arm64"
              "sha256-fG3oKBt780NAI5wNh49lO7YumbRYigBHtRVAjaIfKUc="
            ];
            # FIXME: This won't work because `clarinet` is dynamically linked.
            x86_64-linux = [
              "linux-x64-glibc"
              "sha256-o6JNpWTqCIGJGD65na6JU7dM0Y0EPuaeKHRfy3xfnuo="
            ];
            x86_64-darwin = [
              "darwin-x64"
              "sha256-zjUvRPLN08PQAcX9B44FbITgjaKNQZsLCJgUsr54358="
            ];
          }
          .${system};
      in
      fetchzip {
        url = "https://github.com/hirosystems/${pname}/releases/download/${version}/${pname}-${
          builtins.elemAt architecture_and_hash 0
        }.tar.gz";
        hash = builtins.elemAt architecture_and_hash 1;
      };

    phases = [ "installPhase" ];
    installPhase = ''
      runHook preInstall
      install -Dm755 $src/clarinet $out/bin/clarinet
      runHook postInstall
    '';
  };
}
