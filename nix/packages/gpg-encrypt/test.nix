{ stdenv, gnupg, gpg-encrypt }:

stdenv.mkDerivation {
  name = "gpg-encrypt-test";

  nativeBuildInputs = [ gnupg gpg-encrypt ];

  buildCommand = ''
    set -e

    # Create a test directory
    TESTDIR=$(mktemp -d)
    cd $TESTDIR

    echo "=== GPG Encrypt Integration Test ==="
    echo ""

    # Create a common GPG home for encryption (will import all public keys)
    ENCRYPT_GNUPGHOME="$TESTDIR/gnupg-encrypt"
    mkdir -p "$ENCRYPT_GNUPGHOME"
    chmod 700 "$ENCRYPT_GNUPGHOME"

    # Create 3 separate GPG home directories and generate keys
    echo "Step 1: Generating 3 test GPG keys..."
    for i in 1 2 3; do
      GNUPGHOME_DIR="$TESTDIR/gnupg-$i"
      mkdir -p "$GNUPGHOME_DIR"
      chmod 700 "$GNUPGHOME_DIR"

      export GNUPGHOME="$GNUPGHOME_DIR"

      # Generate key with batch mode
      cat > "$TESTDIR/keygen-$i.batch" <<EOF
    %no-protection
    Key-Type: RSA
    Key-Length: 2048
    Name-Real: Test User $i
    Name-Email: test$i@example.com
    Expire-Date: 0
    %commit
    EOF

      ${gnupg}/bin/gpg --batch --gen-key "$TESTDIR/keygen-$i.batch" 2>&1 | grep -v "^gpg:" || true

      # Extract the key fingerprint
      KEY_FPR=$(${gnupg}/bin/gpg --with-colons --list-keys "test$i@example.com" | grep '^fpr' | head -1 | cut -d: -f10)
      echo "  Generated key $i: $KEY_FPR"

      # Export public key and import into encryption keyring
      ${gnupg}/bin/gpg --export "test$i@example.com" > "$TESTDIR/pubkey-$i.gpg"
      GNUPGHOME="$ENCRYPT_GNUPGHOME" ${gnupg}/bin/gpg --batch --import "$TESTDIR/pubkey-$i.gpg" 2>&1 | grep -v "^gpg:" || true

      # Set ultimate trust on the imported key
      echo "$KEY_FPR:6:" | GNUPGHOME="$ENCRYPT_GNUPGHOME" ${gnupg}/bin/gpg --batch --import-ownertrust 2>&1 | grep -v "^gpg:" || true
    done

    echo ""
    echo "Step 2: Creating test data..."
    TEST_MESSAGE="This is a secret test message for integration testing."
    echo "$TEST_MESSAGE" > "$TESTDIR/plaintext.txt"
    echo "  Test message: $TEST_MESSAGE"

    echo ""
    echo "Step 3: Encrypting using --email for each recipient..."
    # Test encrypting to each individual email
    for i in 1 2 3; do
      echo -n "  Encrypting with test$i@example.com... "
      if ! GNUPGHOME="$ENCRYPT_GNUPGHOME" ${gpg-encrypt}/bin/gpg-encrypt --email "test$i@example.com" \
        --output "$TESTDIR/encrypted-$i.gpg" \
        "$TESTDIR/plaintext.txt" 2>&1; then
        echo "✗ FAILED"
        exit 1
      fi
      echo "✓"
    done
    echo "  ✓ Email-based encryption successful"

    echo ""
    echo "Step 4: Verifying each key can decrypt its encrypted file..."
    SUCCESS_COUNT=0
    for i in 1 2 3; do
      GNUPGHOME_DIR="$TESTDIR/gnupg-$i"
      export GNUPGHOME="$GNUPGHOME_DIR"

      echo -n "  Testing key $i (test$i@example.com)... "

      # Attempt to decrypt the email-specific encrypted version
      DECRYPTED=$(${gnupg}/bin/gpg --batch --decrypt "$TESTDIR/encrypted-$i.gpg" 2>/dev/null || echo "DECRYPT_FAILED")

      if [ "$DECRYPTED" = "$TEST_MESSAGE" ]; then
        echo "✓ SUCCESS"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      else
        echo "✗ FAILED"
        echo "    Expected: $TEST_MESSAGE"
        echo "    Got: $DECRYPTED"
        exit 1
      fi
    done

    echo ""
    if [ $SUCCESS_COUNT -eq 3 ]; then
      echo "=== All Tests Passed! ==="
      echo "  ✓ Generated 3 GPG keys"
      echo "  ✓ Encrypted with --email (per recipient)"
      echo "  ✓ All 3 keys can decrypt their encrypted message"
      echo ""

      # Create success marker
      mkdir -p $out
      echo "All tests passed" > $out/test-result.txt
      echo "Test completed successfully at $(date)" >> $out/test-result.txt
    else
      echo "ERROR: Only $SUCCESS_COUNT/3 decryption tests passed"
      exit 1
    fi

    # Cleanup
    rm -rf $TESTDIR
  '';
}
