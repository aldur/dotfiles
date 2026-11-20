package io.github.aldur.avfsshagent;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import io.github.aldur.avfsshagent.core.PinTrustManager;
import java.io.IOException;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.X509ExtendedKeyManager;
import javax.security.auth.x500.X500Principal;

/**
 * The TLS client key of the app and its self-signed certificate. The key is in the Android
 * Keystore and cannot leave it.
 */
final class Identity extends X509ExtendedKeyManager {
    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String ALIAS = "tls";

    private final PrivateKey key;
    private final X509Certificate certificate;

    private Identity(PrivateKey key, X509Certificate certificate) {
        this.key = key;
        this.certificate = certificate;
    }

    /** Loads the key. Makes it at the first call. Can be slow: do not call on the main thread. */
    static Identity load() throws GeneralSecurityException, IOException {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE);
            generator.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    // The TLS stack hashes the handshake itself and signs with NONEwithECDSA.
                    // The Keystore signs the certificate with SHA-256.
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
                    .setCertificateSubject(new X500Principal("CN=avf-ssh-agent"))
                    .build());
            generator.generateKeyPair();
        }
        PrivateKey key = (PrivateKey) store.getKey(ALIAS, null);
        X509Certificate certificate = (X509Certificate) store.getCertificate(ALIAS);
        if (key == null || certificate == null) {
            throw new KeyStoreException("the Keystore entry of the TLS key is not complete");
        }
        return new Identity(key, certificate);
    }

    KeyManager[] keyManagers() {
        return new KeyManager[] {this};
    }

    /** Returns the pin that the bridge stores for this app. */
    String pin() {
        return PinTrustManager.pin(certificate);
    }

    @Override
    public String chooseClientAlias(String[] keyTypes, Principal[] issuers, Socket socket) {
        return ALIAS;
    }

    @Override
    public String chooseEngineClientAlias(String[] keyTypes, Principal[] issuers, SSLEngine engine) {
        return ALIAS;
    }

    @Override
    public String[] getClientAliases(String keyType, Principal[] issuers) {
        return new String[] {ALIAS};
    }

    @Override
    public X509Certificate[] getCertificateChain(String alias) {
        return new X509Certificate[] {certificate};
    }

    @Override
    public PrivateKey getPrivateKey(String alias) {
        return key;
    }

    @Override
    public String chooseServerAlias(String keyType, Principal[] issuers, Socket socket) {
        return null;
    }

    @Override
    public String[] getServerAliases(String keyType, Principal[] issuers) {
        return null;
    }
}
