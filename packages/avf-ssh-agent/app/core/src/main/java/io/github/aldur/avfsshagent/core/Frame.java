package io.github.aldur.avfsshagent.core;

import java.io.DataInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;

/** One frame: {@code uint32 length || byte type || uint32 conn || payload}. */
final class Frame {
    static final int MESSAGE = 1;
    static final int CLOSE = 2;
    static final int PING = 3;
    static final int PONG = 4;
    static final int PAIR = 5;

    static final int MAX_PAYLOAD = 262144;
    private static final int HEADER = 5;

    final int type;
    final int conn;
    final byte[] payload;

    Frame(int type, int conn, byte[] payload) {
        this.type = type;
        this.conn = conn;
        this.payload = payload;
    }

    static Frame read(DataInputStream in) throws IOException {
        int length = in.readInt();
        if (length < HEADER || length > MAX_PAYLOAD + HEADER) {
            throw new IOException("bad frame length");
        }
        int type = in.readUnsignedByte();
        int conn = in.readInt();
        byte[] payload = new byte[length - HEADER];
        in.readFully(payload);
        return new Frame(type, conn, payload);
    }

    static byte[] encode(int type, int conn, byte[] payload) {
        if (payload.length > MAX_PAYLOAD) {
            throw new IllegalArgumentException("payload too large");
        }
        return ByteBuffer.allocate(4 + HEADER + payload.length)
                .putInt(HEADER + payload.length)
                .put((byte) type)
                .putInt(conn)
                .put(payload)
                .array();
    }
}
