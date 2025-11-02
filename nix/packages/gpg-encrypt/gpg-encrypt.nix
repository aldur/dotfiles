{ stdenv, lib, gnupg, makeWrapper, fetchurl }:
let
  # Fetch the GPG public keys from GitHub
  # This ensures the keys are versioned and tracked via Nix
  gpgKeysFile = fetchurl {
    url = "https://github.com/aldur.gpg";
    sha256 = "c751fef8ea9ac7f65a727b1382ead115623d23efc4ef06f9a63f0f5dfedf866c";
  };

  # Extract key fingerprints from the GPG public key file
  # These will be used as recipients for encryption
  keysFile = stdenv.mkDerivation {
    name = "gpg-encrypt-keys";
    nativeBuildInputs = [ gnupg ];
    buildCommand = ''
      export GNUPGHOME=$(mktemp -d)
      ${gnupg}/bin/gpg --with-colons --import-options show-only --import ${gpgKeysFile} 2>&1 \
        | grep '^fpr' \
        | cut -d: -f10 \
        > $out

      if [ ! -s $out ]; then
        echo "Error: No key fingerprints extracted" >&2
        exit 1
      fi
    '';
  };
in
stdenv.mkDerivation rec {
  pname = "gpg-encrypt";
  version = "0.1.0";

  src = builtins.path {
    path = ./.;
    name = "gpg-encrypt";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ gnupg ];

  phases = [ "installPhase" "fixupPhase" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/gpg-encrypt
    cp ${src}/gpg-encrypt.sh $out/bin/gpg-encrypt
    chmod +x $out/bin/gpg-encrypt

    # Install the keys file
    cp ${keysFile} $out/share/gpg-encrypt/default-keys.txt

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/gpg-encrypt \
      --prefix PATH : ${gnupg}/bin \
      --set GPG_ENCRYPT_DEFAULT_KEYS $out/share/gpg-encrypt/default-keys.txt
  '';

  meta = with lib; {
    description = "GPG encryption wrapper with support for multiple recipients from a key file";
    platforms = platforms.unix;
  };
}
