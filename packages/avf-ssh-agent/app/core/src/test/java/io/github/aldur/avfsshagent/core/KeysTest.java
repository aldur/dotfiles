package io.github.aldur.avfsshagent.core;

import static io.github.aldur.avfsshagent.core.TestSupport.blob;
import static io.github.aldur.avfsshagent.core.TestSupport.check;
import static io.github.aldur.avfsshagent.core.TestSupport.checkEquals;
import static io.github.aldur.avfsshagent.core.TestSupport.checkRefused;
import static io.github.aldur.avfsshagent.core.TestSupport.run;
import static io.github.aldur.avfsshagent.core.TestSupport.sign;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.util.Arrays;
import java.util.Base64;

/** Tests of the fingerprint, the served key blob and the host key signatures. */
final class KeysTest {
    private static final byte[] DATA = SshKeys.ascii("a session ID of 32 bytes ........");

    private KeysTest() {}

    public static void main(String[] args) {
        run("fingerprint is the same as ssh-keygen -l", () -> {
            byte[] key = Base64.getDecoder()
                    .decode("AAAAC3NzaC1lZDI1NTE5AAAAIK5Nqoivx24+/Ri7KODCrxdaXZgBRPYQ2f3SVjrhdRZD");
            checkEquals("SHA256:Lv+M12aQcIHkgeXg3jNQfTZgDJPxYz0/FMPJsXIHXUQ", SshKeys.fingerprint(key));
        });
        run("served key blob", () -> {
            KeyPair key = TestSupport.ecKey("secp256r1");
            byte[] served = SshKeys.p256Blob((ECPublicKey) key.getPublic());
            checkEquals(104, served.length);
            SshKeys.verify(served, DATA, sign(key, "ecdsa-sha2-nistp256", DATA));
            try {
                SshKeys.p256Blob((ECPublicKey) TestSupport.ecKey("secp384r1").getPublic());
            } catch (IllegalArgumentException e) {
                return;
            }
            throw new AssertionError("P-384 key accepted");
        });
        run("self-test of the host key verification", () -> {
            checkEquals("{ssh-ed25519=ok, ecdsa-sha2-nistp256=ok, ecdsa-sha2-nistp384=ok,"
                    + " ecdsa-sha2-nistp521=ok, rsa-sha2-256=ok, rsa-sha2-512=ok}", SshKeys.selfTest().toString());
        });
        run("DER signature of the served key", () -> {
            KeyPair key = TestSupport.ecKey("secp256r1");
            byte[] served = SshKeys.p256Blob((ECPublicKey) key.getPublic());
            Signature signer = Signature.getInstance("SHA256withECDSA");
            signer.initSign(key.getPrivate());
            signer.update(DATA);
            byte[] der = signer.sign();
            SshKeys.verifyServed(served, DATA, der);
            checkRefused("bad host key signature", () -> SshKeys.verifyServed(served, SshKeys.ascii("other"), der));
        });
        run("fixed-length integers", () -> {
            check(Arrays.equals(SshKeys.fixed(BigInteger.ONE, 2), TestSupport.bytes(0, 1)), "short value");
            check(Arrays.equals(SshKeys.fixed(BigInteger.valueOf(0xff00), 2), TestSupport.bytes(0xff, 0)),
                    "high-bit value");
        });

        for (String curve : new String[] {"secp256r1", "secp384r1", "secp521r1"}) {
            run("host key signature ECDSA " + curve, () -> {
                KeyPair key = TestSupport.ecKey(curve);
                checkGoodAndBad(key, TestSupport.keyType(key.getPublic()));
            });
        }
        run("host key signature Ed25519", () -> checkGoodAndBad(TestSupport.ed25519Key(), "ssh-ed25519"));
        KeyPair[] rsa = new KeyPair[1];
        run("host key signature rsa-sha2-256", () -> {
            rsa[0] = TestSupport.rsaKey(2048);
            checkGoodAndBad(rsa[0], "rsa-sha2-256");
        });
        run("host key signature rsa-sha2-512", () -> checkGoodAndBad(rsa[0], "rsa-sha2-512"));
        run("SHA-1 ssh-rsa signature is refused", () ->
                checkRefused("unsupported host key signature algorithm",
                        () -> SshKeys.verify(blob(rsa[0].getPublic()), DATA, sign(rsa[0], "ssh-rsa", DATA))));
        run("RSA signature without leading zero bytes", () -> {
            byte[] hostKey = blob(rsa[0].getPublic());
            for (int i = 0; i < 2000; i++) {
                byte[] data = SshKeys.ascii("data " + i);
                SshReader in = new SshReader(sign(rsa[0], "rsa-sha2-256", data));
                in.readText();
                byte[] signature = in.readString();
                if (signature[0] != 0) {
                    continue;
                }
                byte[] stripped = Arrays.copyOfRange(signature, 1, signature.length);
                SshKeys.verify(hostKey, data,
                        new SshWriter().writeText("rsa-sha2-256").writeString(stripped).toByteArray());
                return;
            }
            throw new AssertionError("no signature with a leading zero byte");
        });
        run("short RSA key is refused", () -> {
            KeyPair key = TestSupport.rsaKey(512);
            checkRefused("bad host key",
                    () -> SshKeys.verify(blob(key.getPublic()), DATA, sign(key, "rsa-sha2-256", DATA)));
        });
        run("signature algorithm of another key type is refused", () -> {
            KeyPair p256 = TestSupport.ecKey("secp256r1");
            KeyPair p384 = TestSupport.ecKey("secp384r1");
            byte[] signature = sign(p384, "ecdsa-sha2-nistp384", DATA);
            checkRefused("algorithm", () -> SshKeys.verify(blob(p256.getPublic()), DATA, signature));
            checkRefused("algorithm",
                    () -> SshKeys.verify(blob(TestSupport.ed25519Key().getPublic()), DATA, signature));
        });
        run("malformed host keys are refused", () -> {
            KeyPair key = TestSupport.ecKey("secp256r1");
            byte[] hostKey = blob(key.getPublic());
            byte[] signature = sign(key, "ecdsa-sha2-nistp256", DATA);

            byte[] offCurve = hostKey.clone();
            offCurve[offCurve.length - 1] ^= 1;
            checkRefused("bad host key", () -> SshKeys.verify(offCurve, DATA, signature));
            checkRefused("truncated",
                    () -> SshKeys.verify(Arrays.copyOf(hostKey, hostKey.length - 1), DATA, signature));
            checkRefused("trailing",
                    () -> SshKeys.verify(Arrays.copyOf(hostKey, hostKey.length + 1), DATA, signature));
            checkRefused("trailing",
                    () -> SshKeys.verify(hostKey, DATA, Arrays.copyOf(signature, signature.length + 1)));
            byte[] unknown = new SshWriter().writeText("ssh-dss").writeString(new byte[4]).toByteArray();
            checkRefused("unsupported host key type", () -> SshKeys.verify(unknown, DATA, signature));
            checkRefused("truncated", () -> SshKeys.verify(new byte[0], DATA, signature));

            byte[] shortEd = new SshWriter().writeText("ssh-ed25519").writeString(new byte[31]).toByteArray();
            byte[] edSignature = new SshWriter().writeText("ssh-ed25519").writeString(new byte[64]).toByteArray();
            checkRefused("bad host key", () -> SshKeys.verify(shortEd, DATA, edSignature));
        });
    }

    private static void checkGoodAndBad(KeyPair key, String algorithm) throws Exception {
        byte[] hostKey = blob(key.getPublic());
        byte[] signature = sign(key, algorithm, DATA);
        SshKeys.verify(hostKey, DATA, signature);

        byte[] otherData = DATA.clone();
        otherData[0] ^= 1;
        checkRefused("bad host key", () -> SshKeys.verify(hostKey, otherData, signature));
        byte[] badSignature = signature.clone();
        badSignature[badSignature.length - 1] ^= 1;
        checkRefused("bad host key", () -> SshKeys.verify(hostKey, DATA, badSignature));
    }
}
