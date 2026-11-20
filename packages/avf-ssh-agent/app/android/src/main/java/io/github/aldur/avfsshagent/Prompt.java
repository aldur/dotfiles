package io.github.aldur.avfsshagent;

import java.util.Arrays;

/**
 * A question to the user: the PIN, or the name of a new host key. A core thread asks and waits.
 * The main thread answers. One prompt can ask more than one time, for example after a wrong PIN.
 */
final class Prompt {
    static final int PIN = 1;
    static final int HOST = 2;

    final int kind;
    /** The destination for a PIN prompt. The fingerprint for a host prompt. */
    final String subject;

    private String message = "";
    private boolean waiting;
    private Object answer;

    Prompt(int kind, String subject) {
        this.kind = kind;
        this.subject = subject;
    }

    /** Starts a question. {@code message} is extra text for the screen. */
    synchronized void begin(String message) {
        this.message = message;
        answer = null;
        waiting = true;
    }

    /** Waits for the answer. Null is a refusal of the user. An interrupt ends the wait. */
    synchronized Object await() throws InterruptedException {
        try {
            while (waiting) {
                wait();
            }
            return answer;
        } catch (InterruptedException e) {
            if (answer instanceof char[]) {
                Arrays.fill((char[]) answer, '\0');
            }
            throw e;
        } finally {
            waiting = false;
        }
    }

    /** Returns false when no thread waits for an answer. */
    synchronized boolean answer(Object value) {
        if (!waiting) {
            return false;
        }
        answer = value;
        waiting = false;
        notifyAll();
        return true;
    }

    synchronized String message() {
        return message;
    }

    synchronized boolean waiting() {
        return waiting;
    }
}
