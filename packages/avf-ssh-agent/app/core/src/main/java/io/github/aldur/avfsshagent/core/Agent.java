package io.github.aldur.avfsshagent.core;

/** The served key and the parts that the platform supplies. */
public final class Agent {
    final byte[] keyBlob;
    final String comment;
    final Signer signer;
    final HostStore hosts;
    final Ui ui;

    /** @param keyBlob the SSH blob of the served key, see {@link SshKeys#p256Blob} */
    public Agent(byte[] keyBlob, String comment, Signer signer, HostStore hosts, Ui ui) {
        this.keyBlob = keyBlob.clone();
        this.comment = comment;
        this.signer = signer;
        this.hosts = hosts;
        this.ui = ui;
    }
}
