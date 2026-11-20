package io.github.aldur.avfsshagent.core;

/** The names that the user gave to host keys. */
public interface HostStore {
    /** Returns the name of the host key blob, or null. */
    String name(byte[] hostKey);

    void store(byte[] hostKey, String name);
}
