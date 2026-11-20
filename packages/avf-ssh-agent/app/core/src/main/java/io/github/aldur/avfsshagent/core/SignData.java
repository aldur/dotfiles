package io.github.aldur.avfsshagent.core;

import java.util.Arrays;

/** The data of a sign request, in one of the two forms that the agent accepts. */
final class SignData {
    private static final byte[] SSHSIG = SshKeys.ascii("SSHSIG");
    private static final int USERAUTH_REQUEST = 50;
    private static final String HOSTBOUND = "publickey-hostbound-v00@openssh.com";

    /** The SSHSIG namespace. Null for user authentication. */
    final String namespace;
    final byte[] sessionId;
    final String user;
    /** The host key of a host-bound request, else null. */
    final byte[] serverHostKey;

    private SignData(String namespace, byte[] sessionId, String user, byte[] serverHostKey) {
        this.namespace = namespace;
        this.sessionId = sessionId;
        this.user = user;
        this.serverHostKey = serverHostKey;
    }

    static SignData parse(byte[] data, byte[] servedKey) throws Refusal {
        SshReader in = new SshReader(data);
        if (data.length >= SSHSIG.length && Arrays.equals(Arrays.copyOf(data, SSHSIG.length), SSHSIG)) {
            in.skip(SSHSIG.length);
            return parseSshsig(in);
        }
        return parseUserAuth(in, servedKey);
    }

    private static SignData parseSshsig(SshReader in) throws Refusal {
        String namespace = in.readText();
        in.readString();
        String hashAlgorithm = in.readText();
        byte[] hash = in.readString();
        in.finish();
        if (namespace.isEmpty()) {
            throw new Refusal("SSHSIG without a namespace");
        }
        boolean sha256 = hashAlgorithm.equals("sha256") && hash.length == 32;
        boolean sha512 = hashAlgorithm.equals("sha512") && hash.length == 64;
        if (!sha256 && !sha512) {
            throw new Refusal("SSHSIG with a bad hash");
        }
        return new SignData(namespace, null, null, null);
    }

    private static SignData parseUserAuth(SshReader in, byte[] servedKey) throws Refusal {
        byte[] sessionId = in.readString();
        if (in.readByte() != USERAUTH_REQUEST) {
            throw new Refusal("unknown sign data");
        }
        String user = in.readText();
        String service = in.readText();
        String method = in.readText();
        boolean hasSignature = in.readBool();
        String algorithm = in.readText();
        byte[] publicKey = in.readString();
        byte[] serverHostKey = method.equals(HOSTBOUND) ? in.readString() : null;
        in.finish();

        if (!service.equals("ssh-connection")) {
            throw new Refusal("user authentication for another service");
        }
        // The session ID alone does not bind the host key, because any key can sign it.
        // Only the host-bound method puts the host key into the signed data.
        if (method.equals("publickey")) {
            throw new Refusal("server without host-bound authentication");
        }
        if (!method.equals(HOSTBOUND)) {
            throw new Refusal("unsupported user authentication method");
        }
        if (!hasSignature || !algorithm.equals(SshKeys.P256)) {
            throw new Refusal("unsupported user authentication algorithm");
        }
        if (!Arrays.equals(publicKey, servedKey)) {
            throw new Refusal("user authentication for another key");
        }
        // An '@' in the user name can make the shown destination ambiguous.
        if (user.isEmpty() || user.contains("@")) {
            throw new Refusal("user name that is not permitted");
        }
        return new SignData(null, sessionId, user, serverHostKey);
    }
}
