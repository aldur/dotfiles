package io.github.aldur.avfsshagent.core;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.security.GeneralSecurityException;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;

/** Connects to the bridge and serves the agent. Connects again after each drop. */
public final class Client {
    public static final String ALPN = "avf-ssh-agent/1";

    public interface Listener {
        /** The TLS handshake is complete. */
        void connected();

        /** The bridge accepted the pairing token. */
        void paired();

        void disconnected(String reason);
    }

    /** Timeouts in milliseconds. Change them only before {@link #run}. */
    public int pingMillis = 30_000;
    public int idleMillis = 75_000;
    public int reconnectMillis = 2_000;
    public int connectMillis = 5_000;

    private static final byte[] EMPTY = new byte[0];

    private final int port;
    private final String pin;
    private final KeyManager[] keyManagers;
    private final Agent agent;
    private final Listener listener;
    private String pairToken;
    private volatile boolean stopped;
    private volatile Socket socket;

    /**
     * @param pin the pin of the bridge certificate
     * @param pairToken the one-time token of the pairing line, or null when the bridge knows
     *     the client certificate
     * @param keyManagers supply the client certificate and its key
     */
    public Client(int port, String pin, String pairToken, KeyManager[] keyManagers, Agent agent,
            Listener listener) {
        this.port = port;
        this.pin = pin;
        this.pairToken = pairToken;
        this.keyManagers = keyManagers;
        this.agent = agent;
        this.listener = listener;
    }

    /** Serves until {@link #stop} or an interrupt. */
    public void run() {
        while (!stopped) {
            String reason;
            try {
                reason = serve();
            } catch (SocketTimeoutException e) {
                reason = "idle timeout";
            } catch (IOException | GeneralSecurityException | RuntimeException e) {
                reason = e.toString();
            }
            listener.disconnected(reason);
            try {
                Thread.sleep(reconnectMillis);
            } catch (InterruptedException e) {
                return;
            }
        }
    }

    public void stop() {
        stopped = true;
        close(socket);
    }

    /** Serves one TLS connection. Returns the reason of its end. */
    private String serve() throws IOException, GeneralSecurityException {
        SSLContext context = SSLContext.getInstance("TLSv1.3");
        context.init(keyManagers, new TrustManager[] {new PinTrustManager(pin)}, null);
        // To close the TCP socket ends the connection at once. To close the TLS socket can block
        // until the read timeout.
        try (Socket tcp = new Socket()) {
            socket = tcp;
            if (stopped) {
                return "stopped";
            }
            tcp.connect(new InetSocketAddress(InetAddress.getByAddress(new byte[] {127, 0, 0, 1}), port),
                    connectMillis);
            tcp.setSoTimeout(idleMillis);
            SSLSocket tls = (SSLSocket) context.getSocketFactory().createSocket(tcp, "127.0.0.1", port, true);
            SSLParameters parameters = tls.getSSLParameters();
            parameters.setProtocols(new String[] {"TLSv1.3"});
            parameters.setApplicationProtocols(new String[] {ALPN});
            tls.setSSLParameters(parameters);
            tls.startHandshake();
            if (!ALPN.equals(tls.getApplicationProtocol())) {
                return "the bridge did not select the protocol " + ALPN;
            }
            listener.connected();

            boolean waitForPair = pairToken != null;
            if (waitForPair) {
                send(tls, tcp, Frame.PAIR, 0, SshKeys.ascii(pairToken));
            }
            Session session = new Session(agent, (conn, message) -> send(tls, tcp, Frame.MESSAGE, conn, message));
            Thread pinger = new Thread(() -> ping(tls, tcp), "avf-ssh-agent-ping");
            pinger.setDaemon(true);
            pinger.start();
            try {
                DataInputStream in = new DataInputStream(new BufferedInputStream(tls.getInputStream()));
                while (true) {
                    Frame frame = Frame.read(in);
                    switch (frame.type) {
                        case Frame.PAIR:
                            if (waitForPair && frame.payload.length == 0) {
                                waitForPair = false;
                                pairToken = null;
                                listener.paired();
                            }
                            break;
                        case Frame.MESSAGE:
                            if (waitForPair) {
                                return "message before the pairing acknowledgement";
                            }
                            session.message(frame.conn, frame.payload);
                            break;
                        case Frame.CLOSE:
                            session.close(frame.conn);
                            break;
                        case Frame.PING:
                            send(tls, tcp, Frame.PONG, 0, EMPTY);
                            break;
                        default:
                            break;
                    }
                }
            } finally {
                pinger.interrupt();
                session.shutdown();
            }
        }
    }

    private void ping(SSLSocket tls, Socket tcp) {
        try {
            while (!tcp.isClosed()) {
                Thread.sleep(pingMillis);
                send(tls, tcp, Frame.PING, 0, EMPTY);
            }
        } catch (InterruptedException e) {
            // The connection ended.
        }
    }

    /** Writes one frame. A write error closes the socket, which stops the read loop. */
    private synchronized void send(SSLSocket tls, Socket tcp, int type, int conn, byte[] payload) {
        try {
            tls.getOutputStream().write(Frame.encode(type, conn, payload));
        } catch (IOException | RuntimeException e) {
            close(tcp);
        }
    }

    private static void close(Socket tcp) {
        try {
            if (tcp != null) {
                tcp.close();
            }
        } catch (IOException e) {
            // The socket is closed.
        }
    }
}
