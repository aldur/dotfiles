package io.github.aldur.avfsshagent.core;

/** The agent refuses a request. The message is the reason. */
public final class Refusal extends Exception {
    private static final long serialVersionUID = 1L;

    public Refusal(String reason) {
        super(reason);
    }
}
