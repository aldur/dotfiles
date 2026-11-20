package io.github.aldur.avfsshagent.core;

import java.util.List;

/** The verified destination of a signature. */
public final class Destination {
    /** The SSHSIG namespace. Null for user authentication. */
    public final String namespace;
    public final String user;
    public final String host;
    /** The fingerprint of the host key. */
    public final String fingerprint;
    /** The names of the hosts that forward the agent, nearest first. */
    public final List<String> forwardedThrough;

    private Destination(String namespace, String user, String host, String fingerprint,
            List<String> forwardedThrough) {
        this.namespace = namespace;
        this.user = user;
        this.host = host;
        this.fingerprint = fingerprint;
        this.forwardedThrough = forwardedThrough;
    }

    public static Destination userAuth(String user, String host, String fingerprint,
            List<String> forwardedThrough) {
        return new Destination(null, user, host, fingerprint, List.copyOf(forwardedThrough));
    }

    public static Destination sshsig(String namespace) {
        return new Destination(namespace, null, null, null, List.of());
    }

    public boolean isSshsig() {
        return namespace != null;
    }

    /** Returns the text to show to the user. */
    @Override
    public String toString() {
        if (isSshsig()) {
            return namespace.equals("git") ? "Sign a git commit" : "Sign (" + namespace + ")";
        }
        String text = user + "@" + host;
        if (!forwardedThrough.isEmpty()) {
            text += " (forwarded through " + String.join(", ", forwardedThrough) + ")";
        }
        return text;
    }
}
