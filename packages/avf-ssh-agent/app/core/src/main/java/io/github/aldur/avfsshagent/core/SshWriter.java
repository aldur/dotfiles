package io.github.aldur.avfsshagent.core;

import java.io.ByteArrayOutputStream;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;

/** Writes SSH wire types. */
final class SshWriter {
    private final ByteArrayOutputStream out = new ByteArrayOutputStream();

    SshWriter writeByte(int value) {
        out.write(value);
        return this;
    }

    SshWriter writeBool(boolean value) {
        return writeByte(value ? 1 : 0);
    }

    SshWriter writeUint32(long value) {
        for (int shift = 24; shift >= 0; shift -= 8) {
            out.write((int) (value >>> shift));
        }
        return this;
    }

    SshWriter writeBytes(byte[] value) {
        out.write(value, 0, value.length);
        return this;
    }

    SshWriter writeString(byte[] value) {
        return writeUint32(value.length).writeBytes(value);
    }

    SshWriter writeText(String value) {
        return writeString(value.getBytes(StandardCharsets.UTF_8));
    }

    SshWriter writeMpint(BigInteger value) {
        return writeString(value.signum() == 0 ? new byte[0] : value.toByteArray());
    }

    byte[] toByteArray() {
        return out.toByteArray();
    }
}
