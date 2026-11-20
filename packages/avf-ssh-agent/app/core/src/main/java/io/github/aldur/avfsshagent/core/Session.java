package io.github.aldur.avfsshagent.core;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;

/**
 * The agent state of one TLS connection. The guest controls all input bytes.
 *
 * <p>Identities and session binds get their answer on the calling thread. Sign requests wait in a
 * queue for one worker thread, because they wait for the user.
 */
public final class Session {
    /** Sends an ssh-agent message to a client connection. */
    public interface Output {
        void send(int conn, byte[] message);
    }

    private static final int FAILURE = 5;
    private static final int SUCCESS = 6;
    private static final int REQUEST_IDENTITIES = 11;
    private static final int IDENTITIES_ANSWER = 12;
    private static final int SIGN_REQUEST = 13;
    private static final int SIGN_RESPONSE = 14;
    private static final int EXTENSION = 27;

    private static final int MAX_BINDS = 16;
    private static final int MAX_QUEUE = 16;

    private static final class Bind {
        final byte[] sessionId;
        final byte[] hostKey;
        final boolean forwarding;

        Bind(byte[] sessionId, byte[] hostKey, boolean forwarding) {
            this.sessionId = sessionId;
            this.hostKey = hostKey;
            this.forwarding = forwarding;
        }
    }

    private static final class SignRequest {
        final int conn;
        final byte[] data;
        final SignData parsed;
        Bind bind;
        List<Bind> through = List.of();
        boolean cancelled;

        SignRequest(int conn, byte[] data, SignData parsed) {
            this.conn = conn;
            this.data = data;
            this.parsed = parsed;
        }
    }

    private final Agent agent;
    private final Output output;
    private final Thread worker = new Thread(this::work, "avf-ssh-agent-sign");

    // The lock of this object guards the fields below.
    private final Map<Integer, List<Bind>> binds = new HashMap<>();
    private final Queue<SignRequest> queue = new ArrayDeque<>();
    private SignRequest current;
    private boolean closed;

    public Session(Agent agent, Output output) {
        this.agent = agent;
        this.output = output;
        worker.setDaemon(true);
        worker.start();
    }

    /** Handles one ssh-agent message of a client connection. */
    public void message(int conn, byte[] payload) {
        byte[] reply;
        try {
            reply = handle(conn, payload);
        } catch (Refusal e) {
            refuse(conn, e.getMessage());
            return;
        } catch (RuntimeException e) {
            refuse(conn, "internal error: " + e);
            return;
        }
        if (reply != null) {
            output.send(conn, reply);
        }
    }

    /** The client connection closed. */
    public void close(int conn) {
        boolean cancelled;
        synchronized (this) {
            binds.remove(conn);
            cancelled = queue.removeIf(request -> request.conn == conn);
            if (current != null && current.conn == conn) {
                cancel(current);
                cancelled = true;
            }
        }
        if (cancelled) {
            agent.ui.cancelled(conn);
        }
    }

    /** The TLS connection ended. Cancels all sign requests and stops the worker. */
    public void shutdown() {
        List<Integer> cancelled = new ArrayList<>();
        synchronized (this) {
            closed = true;
            binds.clear();
            for (SignRequest request : queue) {
                cancelled.add(request.conn);
            }
            queue.clear();
            if (current != null) {
                cancelled.add(current.conn);
                cancel(current);
            }
            notifyAll();
        }
        for (int conn : cancelled) {
            agent.ui.cancelled(conn);
        }
    }

    private void cancel(SignRequest request) {
        request.cancelled = true;
        worker.interrupt();
    }

    /** Returns the reply, or null when a sign request is in the queue. */
    private byte[] handle(int conn, byte[] payload) throws Refusal {
        SshReader in = new SshReader(payload);
        int type = in.readByte();
        switch (type) {
            case REQUEST_IDENTITIES:
                in.finish();
                return new SshWriter()
                        .writeByte(IDENTITIES_ANSWER)
                        .writeUint32(1)
                        .writeString(agent.keyBlob)
                        .writeText(agent.comment)
                        .toByteArray();
            case EXTENSION:
                bind(conn, in);
                return new byte[] {SUCCESS};
            case SIGN_REQUEST:
                enqueue(conn, in);
                return null;
            default:
                throw new Refusal("unsupported message type " + type);
        }
    }

    private void bind(int conn, SshReader in) throws Refusal {
        if (!in.readText().equals("session-bind@openssh.com")) {
            throw new Refusal("unsupported extension");
        }
        byte[] hostKey = in.readString();
        byte[] sessionId = in.readString();
        byte[] signature = in.readString();
        boolean forwarding = in.readBool();
        in.finish();
        if (sessionId.length == 0) {
            throw new Refusal("session bind without a session ID");
        }
        SshKeys.verify(hostKey, sessionId, signature);

        synchronized (this) {
            if (closed) {
                throw new Refusal("connection closed");
            }
            List<Bind> list = binds.computeIfAbsent(conn, key -> new ArrayList<>());
            if (list.size() >= MAX_BINDS) {
                throw new Refusal("too many session binds");
            }
            for (Bind bind : list) {
                if (Arrays.equals(bind.sessionId, sessionId)) {
                    throw new Refusal("session ID bound two times");
                }
            }
            list.add(new Bind(sessionId, hostKey, forwarding));
        }
        agent.ui.bound(conn, SshKeys.fingerprint(hostKey), forwarding);
    }

    private void enqueue(int conn, SshReader in) throws Refusal {
        byte[] keyBlob = in.readString();
        byte[] data = in.readString();
        in.readUint32();
        in.finish();
        if (!Arrays.equals(keyBlob, agent.keyBlob)) {
            throw new Refusal("sign request for another key");
        }
        SignRequest request = new SignRequest(conn, data, SignData.parse(data, agent.keyBlob));

        synchronized (this) {
            if (closed) {
                throw new Refusal("connection closed");
            }
            if (request.parsed.namespace == null) {
                findBind(request);
            }
            if (queue.size() >= MAX_QUEUE) {
                throw new Refusal("too many sign requests");
            }
            queue.add(request);
            notifyAll();
        }
    }

    private void findBind(SignRequest request) throws Refusal {
        List<Bind> through = new ArrayList<>();
        for (Bind bind : binds.getOrDefault(request.conn, List.of())) {
            if (!Arrays.equals(bind.sessionId, request.parsed.sessionId)) {
                if (bind.forwarding) {
                    through.add(bind);
                }
                continue;
            }
            if (bind.forwarding) {
                throw new Refusal("session bind is for agent forwarding, not for authentication");
            }
            byte[] serverHostKey = request.parsed.serverHostKey;
            if (serverHostKey != null && !Arrays.equals(serverHostKey, bind.hostKey)) {
                throw new Refusal("host key differs from the session bind");
            }
            request.bind = bind;
            request.through = through;
            return;
        }
        throw new Refusal("no session bind for this session ID");
    }

    private void work() {
        while (true) {
            SignRequest request;
            synchronized (this) {
                try {
                    while (!closed && queue.isEmpty()) {
                        wait();
                    }
                } catch (InterruptedException e) {
                    return;
                }
                if (closed) {
                    return;
                }
                request = queue.remove();
                current = request;
            }

            byte[] reply = null;
            String reason = null;
            try {
                agent.ui.signing(request.conn, destination(request));
                byte[] signature = EcdsaSig.derToSsh(agent.signer.sign(request.data));
                byte[] blob = new SshWriter().writeText(SshKeys.P256).writeString(signature).toByteArray();
                reply = new SshWriter().writeByte(SIGN_RESPONSE).writeString(blob).toByteArray();
            } catch (Refusal e) {
                reason = e.getMessage();
            } catch (Exception e) {
                reason = "sign failure: " + e;
            }

            synchronized (this) {
                current = null;
                // An interrupt of a cancel must not stay for the next request.
                Thread.interrupted();
                if (request.cancelled) {
                    continue;
                }
            }
            if (reply == null) {
                refuse(request.conn, reason);
            } else {
                output.send(request.conn, reply);
                agent.ui.signed(request.conn);
            }
        }
    }

    private Destination destination(SignRequest request) throws Refusal, InterruptedException {
        if (request.parsed.namespace != null) {
            return Destination.sshsig(request.parsed.namespace);
        }
        String host = name(request.bind.hostKey);
        List<String> through = new ArrayList<>();
        for (Bind bind : request.through) {
            through.add(name(bind.hostKey));
        }
        return Destination.userAuth(
                request.parsed.user, host, SshKeys.fingerprint(request.bind.hostKey), through);
    }

    private String name(byte[] hostKey) throws Refusal, InterruptedException {
        String name = agent.hosts.name(hostKey);
        if (name == null) {
            String fingerprint = SshKeys.fingerprint(hostKey);
            name = agent.ui.nameHost(fingerprint);
            if (name == null) {
                throw new Refusal("unknown host key " + fingerprint);
            }
            agent.hosts.store(hostKey, name);
        }
        return name;
    }

    private void refuse(int conn, String reason) {
        agent.ui.refused(conn, reason);
        output.send(conn, new byte[] {FAILURE});
    }
}
