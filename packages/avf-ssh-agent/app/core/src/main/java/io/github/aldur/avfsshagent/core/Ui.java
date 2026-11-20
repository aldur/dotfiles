package io.github.aldur.avfsshagent.core;

/**
 * What the agent shows to the user. The calls come from the connection thread and from the sign
 * thread. {@code conn} identifies the client connection of the request.
 */
public interface Ui {
    /**
     * Returns a name for an unknown host key, or null to decline. The call can block. An
     * interrupt of the calling thread cancels the call.
     */
    String nameHost(String fingerprint) throws InterruptedException;

    /** A session bind is verified. */
    void bound(int conn, String fingerprint, boolean forwarding);

    /** The signer starts for this destination. */
    void signing(int conn, Destination destination);

    /** The sign request ended with a signature. */
    void signed(int conn);

    /** The agent refused a request. */
    void refused(int conn, String reason);

    /** The client connection closed while its sign request was not complete. */
    void cancelled(int conn);
}
