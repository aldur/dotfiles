{
  stdenv,
  lib,
  gnupg,
  makeWrapper,
  callPackage,
  defaultEmail ? "adrianodl@hotmail.it",
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gpg-encrypt";
  version = "0.2.0";

  src = builtins.path {
    path = ./.;
    name = "gpg-encrypt";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${finalAttrs.src}/gpg-encrypt.sh $out/bin/gpg-encrypt
    chmod +x $out/bin/gpg-encrypt

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/gpg-encrypt \
      --prefix PATH : ${gnupg}/bin \
      --set GPG_ENCRYPT_DEFAULT_EMAIL "${defaultEmail}"
  '';

  # Round-trips encryption against three generated keys. Reachable as
  # `gpg-encrypt.tests`, so `nix-update --test` and the flake check both find
  # it without either being told it exists.
  passthru.tests.integration = callPackage ./test.nix {
    gpg-encrypt = finalAttrs.finalPackage;
  };

  meta = with lib; {
    description = "GPG encryption wrapper that encrypts to all keys for a given email in the GPG keyring";
    platforms = platforms.unix;
    mainProgram = "gpg-encrypt";
  };
})
