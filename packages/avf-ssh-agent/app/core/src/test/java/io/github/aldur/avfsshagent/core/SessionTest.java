package io.github.aldur.avfsshagent.core;

import static io.github.aldur.avfsshagent.core.TestSupport.blob;
import static io.github.aldur.avfsshagent.core.TestSupport.bytes;
import static io.github.aldur.avfsshagent.core.TestSupport.check;
import static io.github.aldur.avfsshagent.core.TestSupport.checkEquals;
import static io.github.aldur.avfsshagent.core.TestSupport.run;

import java.security.KeyPair;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/** Tests of the agent behaviour of one TLS connection. */
final class SessionTest {
    private static final String HOSTBOUND = "publickey-hostbound-v00@openssh.com";
    private static final byte[] SESSION_ID = SshKeys.ascii("session ID one .................");
    private static final byte[] OTHER_SESSION_ID = SshKeys.ascii("session ID two .................");

    private static KeyPair hostKey;
    private static KeyPair otherHostKey;

    private SessionTest() {}

    /** A session with a software key, a host store in memory and a UI that records the calls. */
    private static final class Fixture implements Ui, HostStore, Signer {
        final KeyPair key;
        final byte[] keyBlob;
        final Map<String, String> hosts = new HashMap<>();
        final List<String> events = new ArrayList<>();
        final BlockingQueue<Object[]> replies = new LinkedBlockingQueue<>();
        final Session session;
        String newHostName;
        /** When set, the signer waits for this latch. */
        CountDownLatch release;
        final CountDownLatch signerStarted = new CountDownLatch(1);

        Fixture() throws Exception {
            key = TestSupport.ecKey("secp256r1");
            keyBlob = SshKeys.p256Blob((ECPublicKey) key.getPublic());
            hosts.put(Base64.getEncoder().encodeToString(blob(hostKey.getPublic())), "host.example");
            session = new Session(new Agent(keyBlob, "the comment", this, this, this),
                    (conn, message) -> replies.add(new Object[] {conn, message}));
        }

        /** Sends a request and returns the reply. */
        byte[] request(int conn, byte[] message) throws Exception {
            session.message(conn, message);
            return reply(conn);
        }

        byte[] reply(int conn) throws Exception {
            Object[] reply = replies.poll(10, TimeUnit.SECONDS);
            check(reply != null, "no reply");
            checkEquals(conn, reply[0]);
            return (byte[]) reply[1];
        }

        void checkFailure(int conn, byte[] message, String reasonPart) throws Exception {
            check(Arrays.equals(request(conn, message), bytes(5)), "not a failure reply");
            String last = lastEvent();
            check(last.startsWith("refused " + conn + " ") && last.contains(reasonPart), "unexpected event: " + last);
        }

        byte[] bind(int conn, KeyPair host, byte[] sessionId, boolean forwarding) throws Exception {
            String algorithm = TestSupport.keyType(host.getPublic()).replace("ssh-rsa", "rsa-sha2-256");
            return request(conn, bindMessage(blob(host.getPublic()),
                    sessionId, TestSupport.sign(host, algorithm, sessionId), forwarding));
        }

        void checkBind(int conn, KeyPair host, byte[] sessionId, boolean forwarding) throws Exception {
            check(Arrays.equals(bind(conn, host, sessionId, forwarding), bytes(6)), "bind refused");
        }

        byte[] userAuth(byte[] sessionId, String method, byte[] serverHostKey) {
            return userAuthData(sessionId, "root", "ssh-connection", method, "ecdsa-sha2-nistp256", keyBlob,
                    serverHostKey);
        }

        /** Checks a sign response and its signature over the data. */
        void checkSigned(int conn, byte[] data) throws Exception {
            checkSignature(request(conn, signMessage(keyBlob, data)), data);
        }

        void checkSignature(byte[] reply, byte[] data) throws Exception {
            SshReader in = new SshReader(reply);
            checkEquals(14, in.readByte());
            byte[] signatureBlob = in.readString();
            in.finish();
            SshKeys.verify(keyBlob, data, signatureBlob);
        }

        synchronized String lastEvent() {
            return events.isEmpty() ? "" : events.get(events.size() - 1);
        }

        synchronized boolean hasEvent(String event) {
            return events.contains(event);
        }

        private synchronized void event(String event) {
            events.add(event);
            notifyAll();
        }

        synchronized void awaitEvent(String event) throws InterruptedException {
            long end = System.currentTimeMillis() + 10_000;
            while (!events.contains(event)) {
                long left = end - System.currentTimeMillis();
                check(left > 0, "no event " + event + " in " + events);
                wait(left);
            }
        }

        @Override
        public String nameHost(String fingerprint) {
            event("nameHost " + fingerprint);
            return newHostName;
        }

        @Override
        public void bound(int conn, String fingerprint, boolean forwarding) {
            event("bound " + conn + " " + fingerprint + " " + forwarding);
        }

        @Override
        public void signing(int conn, Destination destination) {
            event("signing " + conn + " " + destination);
        }

        @Override
        public void signed(int conn) {
            event("signed " + conn);
        }

        @Override
        public void refused(int conn, String reason) {
            event("refused " + conn + " " + reason);
        }

        @Override
        public void cancelled(int conn) {
            event("cancelled " + conn);
        }

        @Override
        public synchronized String name(byte[] hostKey) {
            return hosts.get(Base64.getEncoder().encodeToString(hostKey));
        }

        @Override
        public synchronized void store(byte[] hostKey, String name) {
            hosts.put(Base64.getEncoder().encodeToString(hostKey), name);
        }

        @Override
        public byte[] sign(byte[] data) throws Exception {
            signerStarted.countDown();
            if (release != null) {
                try {
                    release.await();
                } catch (InterruptedException e) {
                    event("signer interrupted");
                    throw e;
                }
            }
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(key.getPrivate());
            signature.update(data);
            return signature.sign();
        }
    }

    static byte[] bindMessage(byte[] hostKey, byte[] sessionId, byte[] signature, boolean forwarding) {
        return new SshWriter()
                .writeByte(27)
                .writeText("session-bind@openssh.com")
                .writeString(hostKey)
                .writeString(sessionId)
                .writeString(signature)
                .writeBool(forwarding)
                .toByteArray();
    }

    static byte[] userAuthData(byte[] sessionId, String user, String service, String method, String algorithm,
            byte[] publicKey, byte[] serverHostKey) {
        SshWriter out = new SshWriter()
                .writeString(sessionId)
                .writeByte(50)
                .writeText(user)
                .writeText(service)
                .writeText(method)
                .writeBool(true)
                .writeText(algorithm)
                .writeString(publicKey);
        if (serverHostKey != null) {
            out.writeString(serverHostKey);
        }
        return out.toByteArray();
    }

    static byte[] sshsigData(String namespace) {
        return new SshWriter()
                .writeBytes(SshKeys.ascii("SSHSIG"))
                .writeText(namespace)
                .writeText("")
                .writeText("sha512")
                .writeString(new byte[64])
                .toByteArray();
    }

    static byte[] signMessage(byte[] keyBlob, byte[] data) {
        return new SshWriter().writeByte(13).writeString(keyBlob).writeString(data).writeUint32(0).toByteArray();
    }

    private static byte[] append(byte[] data, int extra) {
        byte[] out = Arrays.copyOf(data, data.length + 1);
        out[data.length] = (byte) extra;
        return out;
    }

    public static void main(String[] args) throws Exception {
        hostKey = TestSupport.ed25519Key();
        otherHostKey = TestSupport.ecKey("secp256r1");
        byte[] hostBlob = blob(hostKey.getPublic());
        String fingerprint = SshKeys.fingerprint(hostBlob);

        run("identities answer", () -> {
            Fixture f = new Fixture();
            byte[] expected = new SshWriter()
                    .writeByte(12).writeUint32(1).writeString(f.keyBlob).writeText("the comment").toByteArray();
            check(Arrays.equals(f.request(1, bytes(11)), expected), "answer");
            f.checkFailure(1, bytes(11, 0), "trailing");
        });
        run("unknown messages are refused", () -> {
            Fixture f = new Fixture();
            f.checkFailure(1, new byte[0], "truncated");
            f.checkFailure(1, bytes(1), "unsupported message type 1");
            f.checkFailure(1, bytes(17, 0, 0, 0, 0), "unsupported message type 17");
            f.checkFailure(1, bytes(19), "unsupported message type 19");
            f.checkFailure(1, new SshWriter().writeByte(27).writeText("query").toByteArray(), "unsupported extension");
            f.checkFailure(1, bytes(27, 0, 0, 0, 9), "truncated");
        });
        run("session-bind: accepted", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            checkEquals("bound 1 " + fingerprint + " false", f.lastEvent());
            f.checkBind(2, TestSupport.rsaKey(2048), SESSION_ID, true);
        });
        run("session-bind: refused", () -> {
            Fixture f = new Fixture();
            byte[] signature = TestSupport.sign(hostKey, "ssh-ed25519", SESSION_ID);
            byte[] good = bindMessage(hostBlob, SESSION_ID, signature, false);
            f.checkFailure(1, bindMessage(hostBlob, OTHER_SESSION_ID, signature, false), "bad host key signature");
            f.checkFailure(1, Arrays.copyOf(good, good.length - 1), "truncated");
            f.checkFailure(1, Arrays.copyOf(good, good.length - 20), "truncated");
            f.checkFailure(1, append(good, 0), "trailing");
            byte[] badBool = good.clone();
            badBool[badBool.length - 1] = 2;
            f.checkFailure(1, badBool, "bool");
            f.checkFailure(1, bindMessage(hostBlob, new byte[0],
                    TestSupport.sign(hostKey, "ssh-ed25519", new byte[0]), false), "without a session ID");
            KeyPair rsa = TestSupport.rsaKey(2048);
            f.checkFailure(1, bindMessage(blob(rsa.getPublic()), SESSION_ID,
                    TestSupport.sign(rsa, "ssh-rsa", SESSION_ID), false), "algorithm");
            check(!f.hasEvent("bound 1 " + fingerprint + " false"), "bind recorded");
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");

            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(1, good, "two times");
            for (int i = 0; i < 15; i++) {
                f.checkBind(1, hostKey, SshKeys.ascii("session " + i), true);
            }
            f.checkFailure(1, bindMessage(hostBlob, OTHER_SESSION_ID,
                    TestSupport.sign(hostKey, "ssh-ed25519", OTHER_SESSION_ID), true), "too many");
        });
        run("sign: user authentication, method hostbound", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkSigned(1, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob));
            check(f.hasEvent("signing 1 root@host.example"), "destination");
            f.awaitEvent("signed 1");
        });
        run("sign refused: method publickey with a good bind", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, "publickey", null)),
                    "server without host-bound authentication");
            check(f.signerStarted.getCount() == 1, "signer used");
        });
        run("sign: SSHSIG", () -> {
            Fixture f = new Fixture();
            f.checkSigned(1, sshsigData("git"));
            check(f.hasEvent("signing 1 Sign a git commit"), "destination");
            f.checkSigned(1, sshsigData("file"));
            check(f.hasEvent("signing 1 Sign (file)"), "destination");
        });
        run("sign refused: no bind", () -> {
            Fixture f = new Fixture();
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");
            f.checkBind(1, hostKey, OTHER_SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");
        });
        run("sign refused: session ID bound on another conn", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(2, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");
            f.checkFailure(2, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");
        });
        run("sign refused: bind with is_forwarding", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, true);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "forwarding");
        });
        run("sign refused: binds are forgotten after CLOSE", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.session.close(1);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)), "no session bind");
        });
        run("sign refused: bad user authentication fields", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            String p256 = "ecdsa-sha2-nistp256";
            byte[] otherKey = SshKeys.p256Blob((ECPublicKey) otherHostKey.getPublic());
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "root", "ssh-userauth", HOSTBOUND, p256, f.keyBlob, hostBlob)),
                    "another service");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "root", "ssh-connection", "hostbased", p256, f.keyBlob, null)),
                    "method");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "root", "ssh-connection", HOSTBOUND, "ssh-ed25519", f.keyBlob, hostBlob)),
                    "algorithm");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "root", "ssh-connection", HOSTBOUND, p256, otherKey, hostBlob)),
                    "user authentication for another key");
            f.checkFailure(1, signMessage(otherKey, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob)),
                    "sign request for another key");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "git@github.com", "ssh-connection", HOSTBOUND, p256, f.keyBlob, hostBlob)),
                    "user name");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "a b", "ssh-connection", HOSTBOUND, p256, f.keyBlob, hostBlob)),
                    "not permitted");
            f.checkFailure(1, signMessage(f.keyBlob,
                    userAuthData(SESSION_ID, "", "ssh-connection", HOSTBOUND, p256, f.keyBlob, hostBlob)),
                    "user name");
            byte[] noSignature = f.userAuth(SESSION_ID, HOSTBOUND, hostBlob);
            noSignature[4 + SESSION_ID.length + 1 + 8 + 18 + 4 + HOSTBOUND.length()] = 0;
            f.checkFailure(1, signMessage(f.keyBlob, noSignature), "algorithm");
            byte[] otherMessage = f.userAuth(SESSION_ID, HOSTBOUND, hostBlob);
            otherMessage[4 + SESSION_ID.length] = 51;
            f.checkFailure(1, signMessage(f.keyBlob, otherMessage), "unknown sign data");
        });
        run("sign refused: hostbound host key mismatch", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, blob(otherHostKey.getPublic()))),
                    "host key differs");
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, null)), "truncated");
        });
        run("sign refused: trailing bytes", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, append(f.userAuth(SESSION_ID, HOSTBOUND, hostBlob), 0)),
                    "trailing");
            f.checkFailure(1, signMessage(f.keyBlob, append(sshsigData("git"), 0)), "trailing");
            f.checkFailure(1, append(signMessage(f.keyBlob, sshsigData("git")), 0), "trailing");
            byte[] message = signMessage(f.keyBlob, sshsigData("git"));
            f.checkFailure(1, Arrays.copyOf(message, message.length - 1), "truncated");
        });
        run("sign refused: arbitrary data", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, new byte[0]), "truncated");
            f.checkFailure(1, signMessage(f.keyBlob, SshKeys.ascii("arbitrary data")), "truncated");
            f.checkFailure(1, signMessage(f.keyBlob, new byte[32]), "unknown sign data");
            f.checkFailure(1, signMessage(f.keyBlob, SshKeys.ascii("SSHSIG")), "truncated");
            f.checkFailure(1, signMessage(f.keyBlob, new SshWriter().writeString(SESSION_ID).toByteArray()),
                    "truncated");
            byte[] badHash = new SshWriter().writeBytes(SshKeys.ascii("SSHSIG"))
                    .writeText("git").writeText("").writeText("sha512").writeString(new byte[32]).toByteArray();
            f.checkFailure(1, signMessage(f.keyBlob, badHash), "bad hash");
            f.checkFailure(1, signMessage(f.keyBlob, sshsigData("")), "namespace");
            byte[] badNamespace = sshsigData("git");
            badNamespace[10] = '\n';
            f.checkFailure(1, signMessage(f.keyBlob, badNamespace), "not permitted");
            check(!f.hasEvent("signed 1"), "something was signed");
        });
        run("unknown host: declined by the UI", () -> {
            Fixture f = new Fixture();
            f.checkBind(1, otherHostKey, SESSION_ID, false);
            f.checkFailure(1, signMessage(f.keyBlob, f.userAuth(SESSION_ID, HOSTBOUND, blob(otherHostKey.getPublic()))),
                    "unknown host key");
            check(f.hasEvent("nameHost " + SshKeys.fingerprint(blob(otherHostKey.getPublic()))), "UI not asked");
            check(f.signerStarted.getCount() == 1, "signer used");
        });
        run("unknown host: named by the UI and stored", () -> {
            Fixture f = new Fixture();
            f.newHostName = "new.example";
            f.checkBind(1, otherHostKey, SESSION_ID, false);
            f.checkSigned(1, f.userAuth(SESSION_ID, HOSTBOUND, blob(otherHostKey.getPublic())));
            check(f.hasEvent("signing 1 root@new.example"), "destination");
            checkEquals("new.example", f.name(blob(otherHostKey.getPublic())));
        });
        run("forwarding: earlier binds are shown as forwarded through", () -> {
            Fixture f = new Fixture();
            f.newHostName = "jump.example";
            f.checkBind(1, otherHostKey, OTHER_SESSION_ID, true);
            f.checkBind(1, hostKey, SESSION_ID, false);
            f.checkSigned(1, f.userAuth(SESSION_ID, HOSTBOUND, hostBlob));
            check(f.hasEvent("signing 1 root@host.example (forwarded through jump.example)"),
                    "destination in " + f.events);
        });
        run("destination text", () -> {
            Destination destination = Destination.userAuth("git", "github.com", "SHA256:x", List.of("a", "b"));
            checkEquals("git@github.com (forwarded through a, b)", destination.toString());
            checkEquals("git@github.com", Destination.userAuth("git", "github.com", "SHA256:x", List.of()).toString());
            check(Destination.sshsig("git").isSshsig() && !destination.isSshsig(), "form");
        });
        run("signer failure is refused", () -> {
            Fixture f = new Fixture();
            Session session = new Session(
                    new Agent(f.keyBlob, "", data -> {
                        throw new IllegalStateException("no key");
                    }, f, f),
                    (conn, message) -> f.replies.add(new Object[] {conn, message}));
            session.message(1, signMessage(f.keyBlob, sshsigData("git")));
            check(Arrays.equals(f.reply(1), bytes(5)), "not a failure reply");
            f.awaitEvent("refused 1 sign failure: java.lang.IllegalStateException: no key");
            session.message(1, bytes(11));
            checkEquals(12, (int) f.reply(1)[0]);
        });
        run("queue: identities and binds are answered while a sign request waits", () -> {
            Fixture f = new Fixture();
            f.release = new CountDownLatch(1);
            byte[] first = sshsigData("first");
            byte[] second = sshsigData("second");
            f.session.message(1, signMessage(f.keyBlob, first));
            f.session.message(2, signMessage(f.keyBlob, second));
            check(f.signerStarted.await(10, TimeUnit.SECONDS), "signer not started");
            checkEquals(12, (int) f.request(3, bytes(11))[0]);
            f.checkBind(3, hostKey, SESSION_ID, false);
            f.checkFailure(3, bytes(99), "unsupported");
            check(!f.hasEvent("signing 2 Sign (second)"), "two sign requests at the same time");
            f.release.countDown();
            f.checkSignature(f.reply(1), first);
            f.checkSignature(f.reply(2), second);
        });
        run("queue: CLOSE cancels a waiting sign request", () -> {
            Fixture f = new Fixture();
            f.release = new CountDownLatch(1);
            byte[] third = sshsigData("third");
            f.session.message(1, signMessage(f.keyBlob, sshsigData("first")));
            f.session.message(2, signMessage(f.keyBlob, sshsigData("second")));
            f.session.message(3, signMessage(f.keyBlob, third));
            check(f.signerStarted.await(10, TimeUnit.SECONDS), "signer not started");
            f.session.close(2);
            check(f.hasEvent("cancelled 2"), "queued request not cancelled");
            f.session.close(1);
            check(f.hasEvent("cancelled 1"), "current request not cancelled");
            f.awaitEvent("signer interrupted");
            f.session.close(4);
            check(!f.hasEvent("cancelled 4"), "cancel without a request");

            f.release.countDown();
            f.checkSignature(f.reply(3), third);
            f.awaitEvent("signed 3");
            check(!f.hasEvent("signing 2 Sign (second)"), "cancelled request reached the signer");
            check(f.replies.isEmpty(), "reply for a cancelled request");
        });
        run("queue: shutdown cancels all sign requests", () -> {
            Fixture f = new Fixture();
            f.release = new CountDownLatch(1);
            f.session.message(1, signMessage(f.keyBlob, sshsigData("first")));
            f.session.message(2, signMessage(f.keyBlob, sshsigData("second")));
            check(f.signerStarted.await(10, TimeUnit.SECONDS), "signer not started");
            f.session.shutdown();
            f.awaitEvent("signer interrupted");
            check(f.hasEvent("cancelled 1") && f.hasEvent("cancelled 2"), "not cancelled");
            f.checkFailure(1, signMessage(f.keyBlob, sshsigData("third")), "connection closed");
        });
        run("queue: too many sign requests are refused", () -> {
            Fixture f = new Fixture();
            f.release = new CountDownLatch(1);
            f.session.message(1, signMessage(f.keyBlob, sshsigData("first")));
            check(f.signerStarted.await(10, TimeUnit.SECONDS), "signer not started");
            for (int conn = 2; conn < 18; conn++) {
                f.session.message(conn, signMessage(f.keyBlob, sshsigData("more")));
            }
            f.checkFailure(18, signMessage(f.keyBlob, sshsigData("more")), "too many sign requests");
            f.session.shutdown();
        });
    }
}
