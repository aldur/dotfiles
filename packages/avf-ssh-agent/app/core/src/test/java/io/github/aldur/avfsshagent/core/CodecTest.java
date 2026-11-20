package io.github.aldur.avfsshagent.core;

import static io.github.aldur.avfsshagent.core.TestSupport.bytes;
import static io.github.aldur.avfsshagent.core.TestSupport.check;
import static io.github.aldur.avfsshagent.core.TestSupport.checkEquals;
import static io.github.aldur.avfsshagent.core.TestSupport.checkRefused;
import static io.github.aldur.avfsshagent.core.TestSupport.hex;
import static io.github.aldur.avfsshagent.core.TestSupport.run;

import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.util.Arrays;

/** Tests of the frame codec, the SSH wire codec, DER signatures and the pairing line. */
final class CodecTest {
    private CodecTest() {}

    public static void main(String[] args) {
        run("frame round trip", () -> {
            byte[] encoded = Frame.encode(Frame.MESSAGE, 7, bytes(11));
            check(Arrays.equals(encoded, bytes(0, 0, 0, 6, 1, 0, 0, 0, 7, 11)), "encoding");
            Frame frame = readFrame(encoded);
            check(frame.type == Frame.MESSAGE && frame.conn == 7 && Arrays.equals(frame.payload, bytes(11)),
                    "decoding");
            check(readFrame(Frame.encode(Frame.PING, 0, new byte[0])).payload.length == 0, "empty payload");
            check(readFrame(Frame.encode(Frame.MESSAGE, 1, new byte[Frame.MAX_PAYLOAD])).payload.length
                    == Frame.MAX_PAYLOAD, "largest payload");
        });
        run("frame malformed", () -> {
            checkIoError(bytes(0, 0, 0, 4, 1, 0, 0, 0));
            checkIoError(bytes(0, 4, 0, 6, 1, 0, 0, 0, 0));
            checkIoError(bytes(0xff, 0xff, 0xff, 0xff, 1, 0, 0, 0, 0));
            checkIoError(bytes(0, 0, 0, 6, 1, 0, 0, 0, 7));
            checkIoError(bytes(0, 0));
        });
        run("wire round trip", () -> {
            byte[] encoded = new SshWriter()
                    .writeByte(200)
                    .writeBool(true)
                    .writeBool(false)
                    .writeUint32(0xfffffffeL)
                    .writeString(bytes(1, 2, 3))
                    .writeText("name")
                    .writeMpint(BigInteger.ZERO)
                    .writeMpint(hex("80"))
                    .writeMpint(hex("7f"))
                    .toByteArray();
            SshReader in = new SshReader(encoded);
            checkEquals(200, in.readByte());
            check(in.readBool() && !in.readBool(), "bool");
            checkEquals(0xfffffffeL, in.readUint32());
            check(Arrays.equals(in.readString(), bytes(1, 2, 3)), "string");
            checkEquals("name", in.readText());
            checkEquals(BigInteger.ZERO, in.readMpint());
            checkEquals(hex("80"), in.readMpint());
            checkEquals(hex("7f"), in.readMpint());
            in.finish();
            check(Arrays.equals(new SshWriter().writeMpint(hex("80")).toByteArray(), bytes(0, 0, 0, 2, 0, 0x80)),
                    "mpint with the high bit set");
        });
        run("wire malformed", () -> {
            checkRefused("truncated", () -> new SshReader(new byte[0]).readByte());
            checkRefused("truncated", () -> new SshReader(bytes(0, 0, 0)).readUint32());
            checkRefused("truncated", () -> new SshReader(bytes(0, 0, 0, 2, 1)).readString());
            checkRefused("truncated", () -> new SshReader(bytes(0xff, 0xff, 0xff, 0xff, 1)).readString());
            checkRefused("truncated", () -> new SshReader(bytes(0x7f, 0xff, 0xff, 0xff, 1)).readString());
            checkRefused("bool", () -> new SshReader(bytes(2)).readBool());
            checkRefused("trailing", () -> new SshReader(bytes(0)).finish());
            checkRefused("leading", () -> new SshReader(bytes(0, 0, 0, 2, 0, 1)).readMpint());
            checkRefused("leading", () -> new SshReader(bytes(0, 0, 0, 1, 0)).readMpint());
            checkRefused("not permitted", () -> new SshReader(bytes(0, 0, 0, 1, '\n')).readText());
            checkRefused("not permitted", () -> new SshReader(bytes(0, 0, 0, 1, ' ')).readText());
            checkRefused("not permitted", () -> new SshReader(bytes(0, 0, 0, 1, 0xc3)).readText());
        });
        run("DER to mpint: usual, high-bit and short values", () -> {
            checkDer(hex("1234"), hex("5678"));
            checkDer(BigInteger.ONE, BigInteger.ONE);
            BigInteger high = BigInteger.ONE.shiftLeft(255).add(BigInteger.TEN);
            checkDer(high, high);
            checkDer(BigInteger.ONE.shiftLeft(100), high);
            BigInteger p521 = BigInteger.ONE.shiftLeft(520);
            checkDer(p521, p521);
            check(Arrays.equals(EcdsaSig.toDer(hex("80"), BigInteger.ONE), bytes(0x30, 7, 2, 2, 0, 0x80, 2, 1, 1)),
                    "DER bytes");
            check(Arrays.equals(EcdsaSig.derToSsh(bytes(0x30, 7, 2, 2, 0, 0x80, 2, 1, 1)),
                    bytes(0, 0, 0, 2, 0, 0x80, 0, 0, 0, 1, 1)), "mpint bytes");
        });
        run("DER malformed", () -> {
            int[][] bad = {
                {},
                {0x30},
                {0x31, 6, 2, 1, 1, 2, 1, 1},
                {0x30, 6, 2, 1, 1, 2, 1},
                {0x30, 5, 2, 1, 1, 2, 1, 1},
                {0x30, 6, 2, 1, 1, 2, 1, 1, 0},
                {0x30, 7, 2, 1, 1, 2, 1, 1, 0},
                {0x30, 3, 2, 1, 1},
                {0x30, 6, 2, 1, 0x80, 2, 1, 1},
                {0x30, 6, 2, 1, 0, 2, 1, 1},
                {0x30, 7, 2, 2, 0, 1, 2, 1, 1},
                {0x30, 5, 2, 0, 2, 1, 1},
                {0x30, 0x81, 6, 2, 1, 1, 2, 1, 1},
                {0x30, 0x82, 0, 6, 2, 1, 1, 2, 1, 1},
                {0x30, 6, 3, 1, 1, 2, 1, 1},
            };
            for (int[] der : bad) {
                checkRefused("DER", () -> EcdsaSig.derToSsh(bytes(der)));
            }
        });
        run("pairing line", () -> {
            String pin = "ab".repeat(32);
            String token = "0123456789abcdef".repeat(2);
            Pairing pairing = Pairing.parse(" avf-ssh-pair:v1:25970:" + pin + ":" + token + "\n");
            check(pairing.port == 25970 && pairing.pin.equals(pin) && pairing.token.equals(token), "fields");
            String[] bad = {
                "",
                "avf-ssh-pair:v2:25970:" + pin + ":" + token,
                "avf-ssh-pair:v1:0:" + pin + ":" + token,
                "avf-ssh-pair:v1:025970:" + pin + ":" + token,
                "avf-ssh-pair:v1:65536:" + pin + ":" + token,
                "avf-ssh-pair:v1:+2597:" + pin + ":" + token,
                "avf-ssh-pair:v1:25970:" + pin.substring(2) + ":" + token,
                "avf-ssh-pair:v1:25970:" + pin.toUpperCase() + ":" + token,
                "avf-ssh-pair:v1:25970:" + pin + ":" + token.substring(2),
                "avf-ssh-pair:v1:25970:" + pin + ":" + token + "a",
                "avf-ssh-pair:v1:25970:" + pin + ":" + token + ":",
                "avf-ssh-pair:v1:25970:" + pin + ":" + token + " x",
                "x avf-ssh-pair:v1:25970:" + pin + ":" + token,
                "avf-ssh-pair:v1:25970:" + pin,
            };
            for (String line : bad) {
                try {
                    Pairing.parse(line);
                } catch (IllegalArgumentException e) {
                    continue;
                }
                throw new AssertionError("accepted: " + line);
            }
        });
    }

    private static Frame readFrame(byte[] encoded) throws IOException {
        return Frame.read(new DataInputStream(new ByteArrayInputStream(encoded)));
    }

    private static void checkIoError(byte[] encoded) {
        try {
            readFrame(encoded);
        } catch (IOException e) {
            return;
        }
        throw new AssertionError("frame accepted");
    }

    private static void checkDer(BigInteger r, BigInteger s) throws Refusal {
        SshReader in = new SshReader(EcdsaSig.derToSsh(EcdsaSig.toDer(r, s)));
        checkEquals(r, in.readMpint());
        checkEquals(s, in.readMpint());
        in.finish();
    }
}
