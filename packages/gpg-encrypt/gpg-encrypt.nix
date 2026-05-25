{ stdenv, lib, gnupg, makeWrapper, defaultEmail ? "adrianodl@hotmail.it" }:

stdenv.mkDerivation rec {
  pname = "gpg-encrypt";
  version = "0.2.0";

  src = builtins.path {
    path = ./.;
    name = "gpg-encrypt";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ gnupg ];

  phases = [ "installPhase" "fixupPhase" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${src}/gpg-encrypt.sh $out/bin/gpg-encrypt
    chmod +x $out/bin/gpg-encrypt

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/gpg-encrypt \
      --prefix PATH : ${gnupg}/bin \
      --set GPG_ENCRYPT_DEFAULT_EMAIL "${defaultEmail}"
  '';

  meta = with lib; {
    description = "GPG encryption wrapper that encrypts to all keys for a given email in the GPG keyring";
    platforms = platforms.unix;
  };
}
