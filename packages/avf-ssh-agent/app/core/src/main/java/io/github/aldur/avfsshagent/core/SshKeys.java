package io.github.aldur.avfsshagent.core;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.ECFieldFp;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.RSAPublicKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/** SSH public key blobs: fingerprint, the served key, and host key signatures. */
public final class SshKeys {
    public static final String P256 = "ecdsa-sha2-nistp256";

    private static final byte[] ED25519_SPKI_PREFIX = {
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
    };
    private static final int MIN_RSA_BITS = 1024;

    // RFC 8032, section 7.1, test 2.
    private static final String ED25519_TEST_KEY =
            "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c";
    private static final String ED25519_TEST_MESSAGE = "72";
    private static final String ED25519_TEST_SIGNATURE =
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
                    + "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00";

    private SshKeys() {}

    /** Returns the fingerprint in the format of {@code ssh-keygen -l}. */
    public static String fingerprint(byte[] blob) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest(blob);
            return "SHA256:" + Base64.getEncoder().withoutPadding().encodeToString(hash);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Returns the SSH blob of a P-256 public key. */
    public static byte[] p256Blob(ECPublicKey key) {
        if (key.getParams().getCurve().getField().getFieldSize() != 256) {
            throw new IllegalArgumentException("not a P-256 key");
        }
        return ecBlob(key);
    }

    private static byte[] ecBlob(ECPublicKey key) {
        int bits = key.getParams().getCurve().getField().getFieldSize();
        int size = (bits + 7) / 8;
        byte[] point = new SshWriter()
                .writeByte(4)
                .writeBytes(fixed(key.getW().getAffineX(), size))
                .writeBytes(fixed(key.getW().getAffineY(), size))
                .toByteArray();
        return new SshWriter()
                .writeText("ecdsa-sha2-nistp" + bits)
                .writeText("nistp" + bits)
                .writeString(point)
                .toByteArray();
    }

    /** Verifies a DER ECDSA signature of the served key over {@code data}. */
    public static void verifyServed(byte[] keyBlob, byte[] data, byte[] der) throws Refusal {
        verify(keyBlob, data, new SshWriter().writeText(P256).writeString(EcdsaSig.derToSsh(der)).toByteArray());
    }

    private interface Check {
        void run() throws Exception;
    }

    /**
     * Verifies one signature of each host key type with the providers of this platform. Returns
     * "ok" or the failure for each type.
     */
    public static Map<String, String> selfTest() {
        byte[] data = ascii("avf-ssh-agent self-test");
        Map<String, String> results = new LinkedHashMap<>();
        selfTest(results, "ssh-ed25519", () -> verify(
                new SshWriter().writeText("ssh-ed25519").writeString(unhex(ED25519_TEST_KEY)).toByteArray(),
                unhex(ED25519_TEST_MESSAGE),
                new SshWriter().writeText("ssh-ed25519").writeString(unhex(ED25519_TEST_SIGNATURE))
                        .toByteArray()));
        String[][] curves = {
            {"secp256r1", "SHA256withECDSA"}, {"secp384r1", "SHA384withECDSA"}, {"secp521r1", "SHA512withECDSA"}
        };
        for (String[] curve : curves) {
            String type = "ecdsa-sha2-nistp" + curve[0].substring(4, 7);
            selfTest(results, type, () -> {
                KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
                generator.initialize(new ECGenParameterSpec(curve[0]));
                KeyPair key = generator.generateKeyPair();
                byte[] signature = EcdsaSig.derToSsh(sign(curve[1], key, data));
                verify(ecBlob((ECPublicKey) key.getPublic()), data,
                        new SshWriter().writeText(type).writeString(signature).toByteArray());
            });
        }
        String[][] hashes = {{"rsa-sha2-256", "SHA256withRSA"}, {"rsa-sha2-512", "SHA512withRSA"}};
        KeyPair[] rsa = new KeyPair[1];
        for (String[] hash : hashes) {
            selfTest(results, hash[0], () -> {
                if (rsa[0] == null) {
                    KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
                    generator.initialize(2048);
                    rsa[0] = generator.generateKeyPair();
                }
                RSAPublicKey key = (RSAPublicKey) rsa[0].getPublic();
                byte[] blob = new SshWriter()
                        .writeText("ssh-rsa")
                        .writeMpint(key.getPublicExponent())
                        .writeMpint(key.getModulus())
                        .toByteArray();
                verify(blob, data,
                        new SshWriter().writeText(hash[0]).writeString(sign(hash[1], rsa[0], data)).toByteArray());
            });
        }
        return results;
    }

    private static void selfTest(Map<String, String> results, String type, Check check) {
        try {
            check.run();
            results.put(type, "ok");
        } catch (Exception e) {
            results.put(type, String.valueOf(e.getCause() != null ? e.getCause() : e));
        }
    }

    private static byte[] sign(String jcaAlgorithm, KeyPair key, byte[] data) throws GeneralSecurityException {
        Signature signer = Signature.getInstance(jcaAlgorithm);
        signer.initSign(key.getPrivate());
        signer.update(data);
        return signer.sign();
    }

    private static byte[] unhex(String digits) {
        byte[] out = new byte[digits.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(digits.substring(2 * i, 2 * i + 2), 16);
        }
        return out;
    }

    /** Returns the unsigned big-endian value in exactly {@code length} bytes. */
    static byte[] fixed(BigInteger value, int length) {
        byte[] bytes = value.toByteArray();
        int start = bytes.length > length && bytes[0] == 0 ? 1 : 0;
        if (value.signum() < 0 || bytes.length - start > length) {
            throw new IllegalArgumentException("value too large");
        }
        byte[] out = new byte[length];
        System.arraycopy(bytes, start, out, length - (bytes.length - start), bytes.length - start);
        return out;
    }

    /** Verifies an SSH signature blob of a host key over {@code data}. */
    static void verify(byte[] hostKey, byte[] data, byte[] signatureBlob) throws Refusal {
        SshReader key = new SshReader(hostKey);
        String keyType = key.readText();
        SshReader signature = new SshReader(signatureBlob);
        String algorithm = signature.readText();
        byte[] sig = signature.readString();
        signature.finish();

        boolean good;
        try {
            switch (keyType) {
                case "ssh-ed25519":
                    good = verifyEd25519(key, algorithm, sig, data);
                    break;
                case "ecdsa-sha2-nistp256":
                    good = verifyEcdsa(key, "nistp256", "secp256r1", "SHA256withECDSA", algorithm, sig, data);
                    break;
                case "ecdsa-sha2-nistp384":
                    good = verifyEcdsa(key, "nistp384", "secp384r1", "SHA384withECDSA", algorithm, sig, data);
                    break;
                case "ecdsa-sha2-nistp521":
                    good = verifyEcdsa(key, "nistp521", "secp521r1", "SHA512withECDSA", algorithm, sig, data);
                    break;
                case "ssh-rsa":
                    good = verifyRsa(key, algorithm, sig, data);
                    break;
                default:
                    throw new Refusal("unsupported host key type");
            }
        } catch (GeneralSecurityException | RuntimeException e) {
            Refusal refusal = new Refusal("bad host key or signature");
            refusal.initCause(e);
            throw refusal;
        }
        if (!good) {
            throw new Refusal("bad host key signature");
        }
    }

    private static boolean verifyEd25519(SshReader key, String algorithm, byte[] sig, byte[] data)
            throws Refusal, GeneralSecurityException {
        byte[] raw = key.readString();
        key.finish();
        if (!algorithm.equals("ssh-ed25519")) {
            throw new Refusal("unsupported host key signature algorithm");
        }
        if (raw.length != 32 || sig.length != 64) {
            throw new Refusal("bad host key or signature");
        }
        byte[] spki = Arrays.copyOf(ED25519_SPKI_PREFIX, ED25519_SPKI_PREFIX.length + 32);
        System.arraycopy(raw, 0, spki, ED25519_SPKI_PREFIX.length, 32);
        PublicKey publicKey = KeyFactory.getInstance("Ed25519").generatePublic(new X509EncodedKeySpec(spki));
        return verify("Ed25519", publicKey, sig, data);
    }

    private static boolean verifyEcdsa(SshReader key, String sshCurve, String jcaCurve, String jcaAlgorithm,
            String algorithm, byte[] sig, byte[] data) throws Refusal, GeneralSecurityException {
        String curveName = key.readText();
        byte[] point = key.readString();
        key.finish();
        if (!algorithm.equals("ecdsa-sha2-" + sshCurve)) {
            throw new Refusal("unsupported host key signature algorithm");
        }
        AlgorithmParameters parameters = AlgorithmParameters.getInstance("EC");
        parameters.init(new ECGenParameterSpec(jcaCurve));
        ECParameterSpec spec = parameters.getParameterSpec(ECParameterSpec.class);
        BigInteger p = ((ECFieldFp) spec.getCurve().getField()).getP();
        int size = (p.bitLength() + 7) / 8;
        if (!curveName.equals(sshCurve) || point.length != 1 + 2 * size || point[0] != 4) {
            throw new Refusal("bad host key or signature");
        }
        BigInteger x = new BigInteger(1, Arrays.copyOfRange(point, 1, 1 + size));
        BigInteger y = new BigInteger(1, Arrays.copyOfRange(point, 1 + size, point.length));
        // Not all providers do this check: the point must be on the curve.
        BigInteger right = x.pow(3).add(spec.getCurve().getA().multiply(x)).add(spec.getCurve().getB()).mod(p);
        if (x.compareTo(p) >= 0 || y.compareTo(p) >= 0 || !y.multiply(y).mod(p).equals(right)) {
            throw new Refusal("bad host key or signature");
        }
        PublicKey publicKey = KeyFactory.getInstance("EC")
                .generatePublic(new ECPublicKeySpec(new ECPoint(x, y), spec));

        SshReader rs = new SshReader(sig);
        BigInteger r = rs.readMpint();
        BigInteger s = rs.readMpint();
        rs.finish();
        if (r.signum() <= 0 || s.signum() <= 0 || r.bitLength() > 8 * size || s.bitLength() > 8 * size) {
            throw new Refusal("bad host key or signature");
        }
        return verify(jcaAlgorithm, publicKey, EcdsaSig.toDer(r, s), data);
    }

    private static boolean verifyRsa(SshReader key, String algorithm, byte[] sig, byte[] data)
            throws Refusal, GeneralSecurityException {
        BigInteger e = key.readMpint();
        BigInteger n = key.readMpint();
        key.finish();
        String jcaAlgorithm;
        if (algorithm.equals("rsa-sha2-256")) {
            jcaAlgorithm = "SHA256withRSA";
        } else if (algorithm.equals("rsa-sha2-512")) {
            jcaAlgorithm = "SHA512withRSA";
        } else {
            throw new Refusal("unsupported host key signature algorithm");
        }
        int size = (n.bitLength() + 7) / 8;
        if (e.signum() <= 0 || n.bitLength() < MIN_RSA_BITS || sig.length > size) {
            throw new Refusal("bad host key or signature");
        }
        PublicKey publicKey = KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(n, e));
        // SSH permits a signature without its leading zero bytes. JCA does not.
        byte[] padded = new byte[size];
        System.arraycopy(sig, 0, padded, size - sig.length, sig.length);
        return verify(jcaAlgorithm, publicKey, padded, data);
    }

    private static boolean verify(String jcaAlgorithm, PublicKey key, byte[] sig, byte[] data)
            throws GeneralSecurityException {
        Signature verifier = Signature.getInstance(jcaAlgorithm);
        verifier.initVerify(key);
        verifier.update(data);
        return verifier.verify(sig);
    }

    static byte[] ascii(String text) {
        return text.getBytes(StandardCharsets.US_ASCII);
    }
}
