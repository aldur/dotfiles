package io.github.aldur.avfsshagent.core;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** The pairing line that the bridge prints: {@code avf-ssh-pair:v1:<port>:<pin>:<token>}. */
public final class Pairing {
    private static final Pattern LINE =
            Pattern.compile("avf-ssh-pair:v1:([1-9][0-9]{0,4}):([0-9a-f]{64}):((?:[0-9a-f]{2}){16,64})");

    public final int port;
    public final String pin;
    public final String token;

    private Pairing(int port, String pin, String token) {
        this.port = port;
        this.pin = pin;
        this.token = token;
    }

    /** Parses a pasted line. White space around the line is permitted. */
    public static Pairing parse(String line) {
        Matcher matcher = LINE.matcher(line.trim());
        if (!matcher.matches()) {
            throw new IllegalArgumentException("not a pairing line");
        }
        int port = Integer.parseInt(matcher.group(1));
        if (port > 65535) {
            throw new IllegalArgumentException("not a pairing line");
        }
        return new Pairing(port, matcher.group(2), matcher.group(3));
    }
}
