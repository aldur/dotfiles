package io.github.aldur.avfsshagent.core;

import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import javax.net.ssl.X509TrustManager;

/** Trusts only the server certificate whose public key has the pin. */
public final class PinTrustManager implements X509TrustManager {
    private final String pin;

    public PinTrustManager(String pin) {
        this.pin = pin;
    }

    /** Returns the lowercase hex SHA-256 of the DER SubjectPublicKeyInfo. */
    public static String pin(Certificate certificate) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(certificate.getPublicKey().getEncoded());
            StringBuilder hex = new StringBuilder();
            for (byte b : hash) {
                hex.append(Character.forDigit((b >> 4) & 0xf, 16)).append(Character.forDigit(b & 0xf, 16));
            }
            return hex.toString();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
        if (chain == null || chain.length == 0 || !pin(chain[0]).equals(pin)) {
            throw new CertificateException("the pin of the bridge certificate is wrong");
        }
    }

    @Override
    public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {
        throw new CertificateException("not a server");
    }

    @Override
    public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
    }
}
