package io.github.aldur.avfsshagent.core;

/** Signs with the private key of the served P-256 key. */
public interface Signer {
    /**
     * Returns the DER ECDSA signature of SHA-256({@code data}).
     *
     * <p>The call can block until the user touches the key. An interrupt of the calling thread
     * cancels the call. Each failure is an exception.
     */
    byte[] sign(byte[] data) throws Exception;
}
