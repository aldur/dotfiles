package io.github.aldur.avfsshagent.core;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Reads SSH wire types from untrusted bytes. Each error is a {@link Refusal}. */
final class SshReader {
    private final byte[] buf;
    private int pos;

    SshReader(byte[] buf) {
        this.buf = buf;
    }

    int readByte() throws Refusal {
        need(1);
        return buf[pos++] & 0xff;
    }

    boolean readBool() throws Refusal {
        int value = readByte();
        if (value > 1) {
            throw new Refusal("malformed bool");
        }
        return value == 1;
    }

    long readUint32() throws Refusal {
        need(4);
        long value = 0;
        for (int i = 0; i < 4; i++) {
            value = value << 8 | (buf[pos++] & 0xff);
        }
        return value;
    }

    byte[] readString() throws Refusal {
        long length = readUint32();
        need(length);
        byte[] value = Arrays.copyOfRange(buf, pos, pos + (int) length);
        pos += (int) length;
        return value;
    }

    /** Reads a string of printable ASCII characters without spaces. */
    String readText() throws Refusal {
        byte[] value = readString();
        for (byte b : value) {
            if (b < 0x21 || b > 0x7e) {
                throw new Refusal("string with a character that is not permitted");
            }
        }
        return new String(value, StandardCharsets.US_ASCII);
    }

    BigInteger readMpint() throws Refusal {
        byte[] value = readString();
        if (value.length == 0) {
            return BigInteger.ZERO;
        }
        BigInteger number = new BigInteger(value);
        // Zero has no bytes.
        if (number.signum() == 0 || number.toByteArray().length != value.length) {
            throw new Refusal("mpint with unnecessary leading bytes");
        }
        return number;
    }

    void skip(int count) throws Refusal {
        need(count);
        pos += count;
    }

    void finish() throws Refusal {
        if (pos != buf.length) {
            throw new Refusal("trailing bytes");
        }
    }

    private void need(long count) throws Refusal {
        if (count > buf.length - pos) {
            throw new Refusal("truncated message");
        }
    }
}
