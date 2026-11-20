package io.github.aldur.avfsshagent.core;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PublicKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.Arrays;

/** A minimal test harness and builders for SSH keys and signatures. */
final class TestSupport {
    interface Case {
        void run() throws Exception;
    }

    private TestSupport() {}

    static void run(String name, Case test) {
        try {
            test.run();
            System.out.println("ok   " + name);
        } catch (Throwable t) {
            System.out.println("FAIL " + name);
            t.printStackTrace(System.out);
            System.exit(1);
        }
    }

    static void check(boolean condition, String what) {
        if (!condition) {
            throw new AssertionError(what);
        }
    }

    static void checkEquals(Object expected, Object actual) {
        check(expected.equals(actual), "expected <" + expected + "> but got <" + actual + ">");
    }

    /** Checks that the case ends in a refusal whose reason contains the text. */
    static void checkRefused(String reasonPart, Case test) throws Exception {
        try {
            test.run();
        } catch (Refusal e) {
            check(e.getMessage().contains(reasonPart), "unexpected reason: " + e.getMessage());
            return;
        }
        throw new AssertionError("not refused");
    }

    static KeyPair ecKey(String curve) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec(curve));
        return generator.generateKeyPair();
    }

    static KeyPair ed25519Key() throws Exception {
        return KeyPairGenerator.getInstance("Ed25519").generateKeyPair();
    }

    static KeyPair rsaKey(int bits) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(bits);
        return generator.generateKeyPair();
    }

    /** Returns the SSH key type, which is also the default signature algorithm. */
    static String keyType(PublicKey key) {
        if (key instanceof ECPublicKey) {
            return "ecdsa-sha2-nistp" + ((ECPublicKey) key).getParams().getCurve().getField().getFieldSize();
        }
        return key instanceof RSAPublicKey ? "ssh-rsa" : "ssh-ed25519";
    }

    static byte[] blob(PublicKey key) {
        SshWriter out = new SshWriter().writeText(keyType(key));
        if (key instanceof ECPublicKey) {
            ECPublicKey ec = (ECPublicKey) key;
            int bits = ec.getParams().getCurve().getField().getFieldSize();
            int size = (bits + 7) / 8;
            byte[] point = new SshWriter()
                    .writeByte(4)
                    .writeBytes(SshKeys.fixed(ec.getW().getAffineX(), size))
                    .writeBytes(SshKeys.fixed(ec.getW().getAffineY(), size))
                    .toByteArray();
            return out.writeText("nistp" + bits).writeString(point).toByteArray();
        }
        if (key instanceof RSAPublicKey) {
            RSAPublicKey rsa = (RSAPublicKey) key;
            return out.writeMpint(rsa.getPublicExponent()).writeMpint(rsa.getModulus()).toByteArray();
        }
        // The last 32 bytes of the X.509 encoding are the raw Ed25519 key.
        byte[] encoded = key.getEncoded();
        return out.writeString(Arrays.copyOfRange(encoded, encoded.length - 32, encoded.length)).toByteArray();
    }

    /** Returns an SSH signature blob. */
    static byte[] sign(KeyPair key, String algorithm, byte[] data) throws Exception {
        String jca;
        switch (algorithm) {
            case "ssh-ed25519": jca = "Ed25519"; break;
            case "ecdsa-sha2-nistp256": jca = "SHA256withECDSA"; break;
            case "ecdsa-sha2-nistp384": jca = "SHA384withECDSA"; break;
            case "ecdsa-sha2-nistp521": jca = "SHA512withECDSA"; break;
            case "ssh-rsa": jca = "SHA1withRSA"; break;
            case "rsa-sha2-256": jca = "SHA256withRSA"; break;
            case "rsa-sha2-512": jca = "SHA512withRSA"; break;
            default: throw new IllegalArgumentException(algorithm);
        }
        Signature signer = Signature.getInstance(jca);
        signer.initSign(key.getPrivate());
        signer.update(data);
        byte[] signature = signer.sign();
        if (algorithm.startsWith("ecdsa-")) {
            signature = EcdsaSig.derToSsh(signature);
        }
        return new SshWriter().writeText(algorithm).writeString(signature).toByteArray();
    }

    static byte[] bytes(int... values) {
        byte[] out = new byte[values.length];
        for (int i = 0; i < values.length; i++) {
            out[i] = (byte) values[i];
        }
        return out;
    }

    static BigInteger hex(String digits) {
        return new BigInteger(digits, 16);
    }
}
