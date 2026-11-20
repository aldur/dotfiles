package io.github.aldur.avfsshagent.core;

import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.util.Arrays;

/** Converts ECDSA signatures between DER and the SSH form {@code mpint r, mpint s}. */
final class EcdsaSig {
    private EcdsaSig() {}

    static byte[] derToSsh(byte[] der) throws Refusal {
        int[] pos = {0};
        int end = header(der, pos, 0x30, der.length);
        if (end != der.length) {
            throw new Refusal("malformed DER signature");
        }
        BigInteger r = integer(der, pos);
        BigInteger s = integer(der, pos);
        if (pos[0] != der.length) {
            throw new Refusal("malformed DER signature");
        }
        return new SshWriter().writeMpint(r).writeMpint(s).toByteArray();
    }

    static byte[] toDer(BigInteger r, BigInteger s) {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        element(body, 0x02, r.toByteArray());
        element(body, 0x02, s.toByteArray());
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        element(out, 0x30, body.toByteArray());
        return out.toByteArray();
    }

    /** Reads a tag and a length. Returns the end offset of the element. */
    private static int header(byte[] der, int[] pos, int tag, int limit) throws Refusal {
        if (limit - pos[0] < 2 || (der[pos[0]++] & 0xff) != tag) {
            throw new Refusal("malformed DER signature");
        }
        int length = der[pos[0]++] & 0xff;
        if (length == 0x81) {
            // The long form is correct only for a length of 128 or more.
            if (pos[0] >= limit || (length = der[pos[0]++] & 0xff) < 0x80) {
                throw new Refusal("malformed DER signature");
            }
        } else if (length > 0x7f) {
            throw new Refusal("malformed DER signature");
        }
        if (length > limit - pos[0]) {
            throw new Refusal("malformed DER signature");
        }
        return pos[0] + length;
    }

    private static BigInteger integer(byte[] der, int[] pos) throws Refusal {
        int end = header(der, pos, 0x02, der.length);
        byte[] bytes = Arrays.copyOfRange(der, pos[0], end);
        pos[0] = end;
        if (bytes.length == 0) {
            throw new Refusal("malformed DER signature");
        }
        BigInteger value = new BigInteger(bytes);
        if (value.signum() <= 0 || value.toByteArray().length != bytes.length) {
            throw new Refusal("malformed DER signature");
        }
        return value;
    }

    private static void element(ByteArrayOutputStream out, int tag, byte[] content) {
        if (content.length > 0xff) {
            throw new IllegalArgumentException("element too long");
        }
        out.write(tag);
        if (content.length > 0x7f) {
            out.write(0x81);
        }
        out.write(content.length);
        out.write(content, 0, content.length);
    }
}
