{ runCommand, gnupg, gpg-encrypt }:
runCommand "gpg-encrypt-test" { nativeBuildInputs = [ gnupg gpg-encrypt ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME" "$PWD/encrypt"
  chmod 700 "$PWD/encrypt"
  trap 'for directory in "$PWD"/key-* "$PWD/encrypt"; do GNUPGHOME="$directory" gpgconf --kill gpg-agent; done' EXIT

  for number in 1 2 3; do
    export GNUPGHOME="$PWD/key-$number"
    mkdir -m 700 "$GNUPGHOME"
    email=shared@example.invalid
    if [ "$number" = 3 ]; then email=other@example.invalid; fi
    gpg --batch --pinentry-mode loopback --passphrase "" \
      --quick-generate-key "Recipient $number <$email>" rsa2048 encr 0
    fingerprint=$(gpg --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')
    gpg --export "$fingerprint" > public.gpg
    GNUPGHOME="$PWD/encrypt" gpg --batch --import public.gpg
    printf '%s:6:\n' "$fingerprint" | GNUPGHOME="$PWD/encrypt" gpg --batch --import-ownertrust
  done

  printf 'Shared recipient fixture\n' > plaintext
  GNUPGHOME="$PWD/encrypt" gpg-encrypt --email shared@example.invalid \
    --output encrypted.gpg plaintext
  for number in 1 2; do
    GNUPGHOME="$PWD/key-$number" gpg --batch --decrypt encrypted.gpg > decrypted
    cmp plaintext decrypted
  done
  if GNUPGHOME="$PWD/key-3" gpg --batch --decrypt encrypted.gpg > decrypted; then
    echo 'An unrelated recipient decrypted the message.' >&2
    exit 1
  fi
  touch "$out"
''
