package io.github.aldur.avfsshagent.core;

import java.math.BigInteger;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Arrays;

/**
 * Verifies Ed25519 signatures as RFC 8032, section 5.1.7. Android has no provider that makes an
 * Ed25519 public key from its bytes. The arithmetic is not constant-time: all inputs are public.
 */
final class Ed25519 {
    private static final BigInteger TWO = BigInteger.valueOf(2);
    private static final BigInteger P = TWO.pow(255).subtract(BigInteger.valueOf(19));
    private static final BigInteger L =
            TWO.pow(252).add(new BigInteger("27742317777372353535851937790883648493"));
    private static final BigInteger D =
            BigInteger.valueOf(-121665).multiply(BigInteger.valueOf(121666).modInverse(P)).mod(P);
    private static final BigInteger SQRT_MINUS_1 = TWO.modPow(P.subtract(BigInteger.ONE).shiftRight(2), P);
    // Points are {X, Y, Z, T} with x = X/Z, y = Y/Z and x * y = T/Z.
    private static final BigInteger[] NEUTRAL = {BigInteger.ZERO, BigInteger.ONE, BigInteger.ONE, BigInteger.ZERO};
    private static final BigInteger[] BASE = decode(basePoint());

    private Ed25519() {}

    /** Returns true when {@code signature} is the signature of {@code message} by {@code publicKey}. */
    static boolean verify(byte[] publicKey, byte[] message, byte[] signature) throws GeneralSecurityException {
        if (publicKey.length != 32 || signature.length != 64) {
            return false;
        }
        BigInteger[] a = decode(publicKey);
        BigInteger s = littleEndian(Arrays.copyOfRange(signature, 32, 64));
        if (a == null || s.compareTo(L) >= 0) {
            return false;
        }
        byte[] r = Arrays.copyOf(signature, 32);
        MessageDigest sha512 = MessageDigest.getInstance("SHA-512");
        sha512.update(r);
        sha512.update(publicKey);
        BigInteger h = littleEndian(sha512.digest(message)).mod(L);
        // The signature is good when s * B - h * A is the point R.
        BigInteger[] minusA = {P.subtract(a[0]), a[1], a[2], P.subtract(a[3])};
        return Arrays.equals(encode(add(multiply(BASE, s), multiply(minusA, h))), r);
    }

    private static byte[] basePoint() {
        byte[] base = new byte[32];
        Arrays.fill(base, (byte) 0x66);
        base[0] = 0x58;
        return base;
    }

    private static BigInteger littleEndian(byte[] bytes) {
        byte[] reversed = new byte[bytes.length];
        for (int i = 0; i < bytes.length; i++) {
            reversed[i] = bytes[bytes.length - 1 - i];
        }
        return new BigInteger(1, reversed);
    }

    /** Returns the point of an encoding of 32 bytes, or null when the encoding is not a point. */
    private static BigInteger[] decode(byte[] encoded) {
        boolean odd = (encoded[31] & 0x80) != 0;
        BigInteger y = littleEndian(encoded).clearBit(255);
        if (y.compareTo(P) >= 0) {
            return null;
        }
        // x * x = u / v.
        BigInteger u = y.multiply(y).subtract(BigInteger.ONE).mod(P);
        BigInteger v = D.multiply(y).multiply(y).add(BigInteger.ONE).mod(P);
        BigInteger x = u.multiply(v.pow(3))
                .multiply(u.multiply(v.pow(7)).modPow(P.subtract(BigInteger.valueOf(5)).shiftRight(3), P))
                .mod(P);
        BigInteger vxx = v.multiply(x).multiply(x).mod(P);
        if (vxx.equals(P.subtract(u).mod(P))) {
            x = x.multiply(SQRT_MINUS_1).mod(P);
        } else if (!vxx.equals(u)) {
            return null;
        }
        if (x.signum() == 0 && odd) {
            return null;
        }
        if (x.testBit(0) != odd) {
            x = P.subtract(x);
        }
        return new BigInteger[] {x, y, BigInteger.ONE, x.multiply(y).mod(P)};
    }

    private static byte[] encode(BigInteger[] point) {
        BigInteger inverse = point[2].modInverse(P);
        BigInteger x = point[0].multiply(inverse).mod(P);
        BigInteger y = point[1].multiply(inverse).mod(P);
        byte[] encoded = new byte[32];
        for (int i = 0; i < 32; i++) {
            encoded[i] = y.shiftRight(8 * i).byteValue();
        }
        if (x.testBit(0)) {
            encoded[31] |= (byte) 0x80;
        }
        return encoded;
    }

    /** RFC 8032, section 5.1.4. The formula is good for all points, also for equal points. */
    private static BigInteger[] add(BigInteger[] p, BigInteger[] q) {
        BigInteger a = p[1].subtract(p[0]).multiply(q[1].subtract(q[0])).mod(P);
        BigInteger b = p[1].add(p[0]).multiply(q[1].add(q[0])).mod(P);
        BigInteger c = p[3].multiply(TWO).multiply(D).multiply(q[3]).mod(P);
        BigInteger d = p[2].multiply(TWO).multiply(q[2]).mod(P);
        BigInteger e = b.subtract(a);
        BigInteger f = d.subtract(c);
        BigInteger g = d.add(c);
        BigInteger h = b.add(a);
        return new BigInteger[] {
            e.multiply(f).mod(P), g.multiply(h).mod(P), f.multiply(g).mod(P), e.multiply(h).mod(P)
        };
    }

    private static BigInteger[] multiply(BigInteger[] point, BigInteger scalar) {
        BigInteger[] result = NEUTRAL;
        for (int i = scalar.bitLength() - 1; i >= 0; i--) {
            result = add(result, result);
            if (scalar.testBit(i)) {
                result = add(result, point);
            }
        }
        return result;
    }
}
