package io.github.aldur.avfsshagent.core;

import static io.github.aldur.avfsshagent.core.TestSupport.bytes;
import static io.github.aldur.avfsshagent.core.TestSupport.check;
import static io.github.aldur.avfsshagent.core.TestSupport.checkEquals;
import static io.github.aldur.avfsshagent.core.TestSupport.run;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.util.Arrays;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.KeyManager;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

/** Tests of the client against a TLS server in this process that stands in for the bridge. */
final class ClientTest {
    private static final char[] PASSWORD = "password".toCharArray();
    private static final String TOKEN = "0123456789abcdef0123456789abcdef";

    private static KeyStore clientStore;
    private static KeyStore bridgeStore;
    private static String bridgePin;

    private ClientTest() {}

    /** The bridge end: a TLS 1.3 server that requires a client certificate of any issuer. */
    private static final class FakeBridge implements AutoCloseable {
        final SSLServerSocket server;
        private SSLSocket socket;
        private DataInputStream in;

        FakeBridge(String alpn) throws Exception {
            X509TrustManager trustAll = new X509TrustManager() {
                @Override
                public void checkClientTrusted(X509Certificate[] chain, String authType) {}

                @Override
                public void checkServerTrusted(X509Certificate[] chain, String authType) {}

                @Override
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
            };
            SSLContext context = SSLContext.getInstance("TLSv1.3");
            context.init(keyManagers(bridgeStore), new TrustManager[] {trustAll}, null);
            server = (SSLServerSocket) context.getServerSocketFactory()
                    .createServerSocket(0, 10, InetAddress.getByAddress(new byte[] {127, 0, 0, 1}));
            SSLParameters parameters = server.getSSLParameters();
            parameters.setProtocols(new String[] {"TLSv1.3"});
            parameters.setApplicationProtocols(new String[] {alpn});
            parameters.setNeedClientAuth(true);
            server.setSSLParameters(parameters);
            server.setSoTimeout(10_000);
        }

        int port() {
            return server.getLocalPort();
        }

        /** Accepts the next connection and completes the handshake. */
        void accept() throws IOException {
            socket = (SSLSocket) server.accept();
            socket.setSoTimeout(10_000);
            socket.startHandshake();
            in = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        }

        String clientPin() throws IOException {
            return PinTrustManager.pin(socket.getSession().getPeerCertificates()[0]);
        }

        Frame read() throws IOException {
            return Frame.read(in);
        }

        void write(int type, int conn, byte[] payload) throws IOException {
            socket.getOutputStream().write(Frame.encode(type, conn, payload));
        }

        void drop() throws IOException {
            socket.close();
        }

        @Override
        public void close() throws IOException {
            if (socket != null) {
                socket.close();
            }
            server.close();
        }
    }

    /** A client on its own thread. Its listener calls go to a queue. */
    private static final class RunningClient implements Client.Listener, Ui, AutoCloseable {
        final BlockingQueue<String> events = new LinkedBlockingQueue<>();
        final Client client;

        RunningClient(int port, String pin, String token) throws Exception {
            byte[] keyBlob = SshKeys.p256Blob((ECPublicKey) clientStore.getCertificate("ssh").getPublicKey());
            Agent agent = new Agent(keyBlob, "comment", data -> {
                throw new IllegalStateException("no signer");
            }, null, this);
            client = new Client(port, pin, token, keyManagers(tlsOnly(clientStore)), agent, this);
            client.reconnectMillis = 100;
        }

        void start() {
            Thread thread = new Thread(client::run);
            thread.setDaemon(true);
            thread.start();
        }

        String next() throws InterruptedException {
            String event = events.poll(10, TimeUnit.SECONDS);
            check(event != null, "no listener call");
            return event;
        }

        @Override
        public void connected() {
            events.add("connected");
        }

        @Override
        public void paired() {
            events.add("paired");
        }

        @Override
        public void disconnected(String reason) {
            events.add("disconnected " + reason);
        }

        @Override
        public String nameHost(String fingerprint) {
            return null;
        }

        @Override
        public void bound(int conn, String fingerprint, boolean forwarding) {}

        @Override
        public void signing(int conn, Destination destination) {}

        @Override
        public void signed(int conn) {}

        @Override
        public void refused(int conn, String reason) {}

        @Override
        public void cancelled(int conn) {}

        @Override
        public void close() {
            client.stop();
        }
    }

    private static KeyManager[] keyManagers(KeyStore store) throws Exception {
        KeyManagerFactory factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        factory.init(store, PASSWORD);
        return factory.getKeyManagers();
    }

    private static KeyStore tlsOnly(KeyStore store) throws Exception {
        KeyStore tls = KeyStore.getInstance("PKCS12");
        tls.load(null, null);
        tls.setKeyEntry("tls", store.getKey("tls", PASSWORD), PASSWORD, store.getCertificateChain("tls"));
        return tls;
    }

    /** Makes a PKCS12 keystore with keytool, one P-256 key for each alias. */
    private static KeyStore makeStore(Path file, String... aliases) throws Exception {
        Path keytool = Path.of(System.getProperty("java.home"), "bin", "keytool");
        for (String alias : aliases) {
            Process process = new ProcessBuilder(keytool.toString(), "-genkeypair", "-keyalg", "EC",
                    "-groupname", "secp256r1", "-alias", alias, "-dname", "CN=" + alias, "-validity", "3650",
                    "-keystore", file.toString(), "-storetype", "PKCS12", "-storepass", new String(PASSWORD))
                    .redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
            checkEquals(0, process.waitFor());
        }
        KeyStore store = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(file)) {
            store.load(in, PASSWORD);
        }
        return store;
    }

    public static void main(String[] args) throws Exception {
        Path directory = Files.createTempDirectory("avf-ssh-agent-test");
        try {
            clientStore = makeStore(directory.resolve("client.p12"), "tls", "ssh");
            bridgeStore = makeStore(directory.resolve("bridge.p12"), "tls");
        } finally {
            Files.deleteIfExists(directory.resolve("client.p12"));
            Files.deleteIfExists(directory.resolve("bridge.p12"));
            Files.delete(directory);
        }
        bridgePin = PinTrustManager.pin(bridgeStore.getCertificate("tls"));

        run("pin format", () -> check(bridgePin.matches("[0-9a-f]{64}"), bridgePin));
        run("client: a wrong pin aborts the handshake", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), "00".repeat(32), TOKEN)) {
                client.start();
                try {
                    bridge.accept();
                    // The handshake is complete for the server only when the client sends data.
                    bridge.read();
                    throw new AssertionError("the client sent a frame");
                } catch (IOException e) {
                    // The client aborted.
                }
                String event = client.next();
                check(event.startsWith("disconnected ") && event.contains("pin"), event);
            }
        });
        run("client: a wrong ALPN protocol ends the connection", () -> {
            try (FakeBridge bridge = new FakeBridge("other/1");
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, null)) {
                client.start();
                try {
                    bridge.accept();
                } catch (IOException e) {
                    // The client aborted.
                }
                check(client.next().startsWith("disconnected "), "connected");
            }
        });
        run("client: pairing, message round trip, PING and PONG", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, TOKEN)) {
                client.start();
                bridge.accept();
                checkEquals(PinTrustManager.pin(clientStore.getCertificate("tls")), bridge.clientPin());
                checkEquals("connected", client.next());

                Frame pair = bridge.read();
                check(pair.type == Frame.PAIR && pair.conn == 0, "first frame is not PAIR");
                checkEquals(TOKEN, new String(pair.payload, "US-ASCII"));
                bridge.write(Frame.PAIR, 0, new byte[0]);
                checkEquals("paired", client.next());

                bridge.write(99, 0, bytes(1, 2, 3));
                bridge.write(Frame.MESSAGE, 7, bytes(11));
                Frame answer = bridge.read();
                check(answer.type == Frame.MESSAGE && answer.conn == 7 && answer.payload[0] == 12, "identities");
                bridge.write(Frame.MESSAGE, 8, bytes(99));
                Frame failure = bridge.read();
                check(failure.type == Frame.MESSAGE && failure.conn == 8 && Arrays.equals(failure.payload, bytes(5)),
                        "failure");

                bridge.write(Frame.PING, 0, new byte[0]);
                Frame pong = bridge.read();
                check(pong.type == Frame.PONG && pong.conn == 0 && pong.payload.length == 0, "PONG");
            }
        });
        run("client: a message before the pairing acknowledgement ends the connection", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, TOKEN)) {
                client.start();
                bridge.accept();
                checkEquals("connected", client.next());
                bridge.write(Frame.MESSAGE, 1, bytes(11));
                check(client.next().contains("before the pairing"), "not disconnected");
            }
        });
        run("client: reconnect after a drop, without the token after pairing", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, TOKEN)) {
                client.start();
                bridge.accept();
                checkEquals(Frame.PAIR, bridge.read().type);
                bridge.write(Frame.PAIR, 0, new byte[0]);
                checkEquals("connected", client.next());
                checkEquals("paired", client.next());
                bridge.drop();
                check(client.next().startsWith("disconnected "), "not disconnected");

                bridge.accept();
                checkEquals("connected", client.next());
                bridge.write(Frame.MESSAGE, 9, bytes(11));
                Frame answer = bridge.read();
                check(answer.type == Frame.MESSAGE && answer.conn == 9, "first frame is not the answer");
            }
        });
        run("client: reconnect while the bridge does not listen", () -> {
            int port;
            try (FakeBridge bridge = new FakeBridge(Client.ALPN)) {
                port = bridge.port();
            }
            try (RunningClient client = new RunningClient(port, bridgePin, null)) {
                client.start();
                check(client.next().startsWith("disconnected "), "connected");
                check(client.next().startsWith("disconnected "), "connected");
            }
        });
        run("client: sends PING", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, null)) {
                client.client.pingMillis = 50;
                client.start();
                bridge.accept();
                for (int i = 0; i < 2; i++) {
                    Frame ping = bridge.read();
                    check(ping.type == Frame.PING && ping.conn == 0 && ping.payload.length == 0, "PING");
                }
            }
        });
        run("client: idle timeout", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, null)) {
                client.client.idleMillis = 300;
                client.start();
                bridge.accept();
                checkEquals("connected", client.next());
                bridge.write(Frame.PONG, 0, new byte[0]);
                checkEquals("disconnected idle timeout", client.next());
            }
        });
        run("client: a frame that is too large ends the connection", () -> {
            try (FakeBridge bridge = new FakeBridge(Client.ALPN);
                    RunningClient client = new RunningClient(bridge.port(), bridgePin, null)) {
                client.start();
                bridge.accept();
                checkEquals("connected", client.next());
                bridge.socket.getOutputStream().write(bytes(0, 4, 0, 6, 1, 0, 0, 0, 1));
                check(client.next().contains("bad frame length"), "not disconnected");
            }
        });
    }
}
