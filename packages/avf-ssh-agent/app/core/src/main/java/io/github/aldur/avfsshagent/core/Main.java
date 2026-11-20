package io.github.aldur.avfsshagent.core;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import javax.net.ssl.KeyManagerFactory;

/** Runs the agent on a desktop JVM with a software key, for the end-to-end test. */
public final class Main implements Ui, Client.Listener, HostStore {
    private static final String USAGE = "usage: --keystore FILE --storepass PASS"
            + " (--print-public-key | --print-pin | (--pair LINE | --port N --pin HEX) --hosts FILE"
            + " [--name-new-hosts NAME]) [--comment TEXT]";

    private final Path hostsFile;
    private final String newHostName;
    private final Map<String, String> hosts = new HashMap<>();

    private Main(Path hostsFile, String newHostName) throws IOException {
        this.hostsFile = hostsFile;
        this.newHostName = newHostName;
        if (Files.exists(hostsFile)) {
            for (String line : Files.readAllLines(hostsFile)) {
                String[] parts = line.trim().split("\\s+", 2);
                if (parts.length == 2) {
                    hosts.put(parts[0], parts[1]);
                }
            }
        }
    }

    public static void main(String[] args) throws Exception {
        Map<String, String> options = new HashMap<>();
        for (int i = 0; i < args.length; i++) {
            boolean flag = args[i].equals("--print-public-key") || args[i].equals("--print-pin");
            if (!args[i].startsWith("--") || (!flag && i + 1 == args.length)) {
                System.err.println(USAGE);
                System.exit(2);
            }
            options.put(args[i], flag ? "" : args[++i]);
        }
        if (!options.containsKey("--keystore") || !options.containsKey("--storepass")) {
            System.err.println(USAGE);
            System.exit(2);
        }

        char[] password = options.get("--storepass").toCharArray();
        KeyStore store = KeyStore.getInstance("PKCS12");
        try (InputStream in = new FileInputStream(options.get("--keystore"))) {
            store.load(in, password);
        }
        String comment = options.getOrDefault("--comment", "avf-ssh-agent");
        byte[] keyBlob = SshKeys.p256Blob((ECPublicKey) store.getCertificate("ssh").getPublicKey());

        if (options.containsKey("--print-pin")) {
            System.out.println(PinTrustManager.pin(store.getCertificate("tls")));
            return;
        }
        if (options.containsKey("--print-public-key")) {
            System.out.println(SshKeys.P256 + " " + Base64.getEncoder().encodeToString(keyBlob) + " " + comment);
            return;
        }

        int port;
        String pin;
        String token = null;
        if (options.containsKey("--pair")) {
            Pairing pairing = Pairing.parse(options.get("--pair"));
            port = pairing.port;
            pin = pairing.pin;
            token = pairing.token;
        } else if (options.containsKey("--port") && options.containsKey("--pin")) {
            port = Integer.parseInt(options.get("--port"));
            pin = options.get("--pin");
        } else {
            System.err.println(USAGE);
            System.exit(2);
            return;
        }
        if (!options.containsKey("--hosts")) {
            System.err.println(USAGE);
            System.exit(2);
        }

        // The key manager must see only the TLS key. If not, it can select the SSH key.
        KeyStore tlsStore = KeyStore.getInstance("PKCS12");
        tlsStore.load(null, null);
        tlsStore.setKeyEntry("tls", store.getKey("tls", password), password, store.getCertificateChain("tls"));
        KeyManagerFactory keyManagers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        keyManagers.init(tlsStore, password);

        PrivateKey sshKey = (PrivateKey) store.getKey("ssh", password);
        Signer signer = data -> {
            Signature signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(sshKey);
            signature.update(data);
            return signature.sign();
        };

        Main main = new Main(Path.of(options.get("--hosts")), options.get("--name-new-hosts"));
        Agent agent = new Agent(keyBlob, comment, signer, main, main);
        new Client(port, pin, token, keyManagers.getKeyManagers(), agent, main).run();
    }

    private static synchronized void print(String line) {
        System.out.println(line.replaceAll("\\p{Cntrl}", " "));
        System.out.flush();
    }

    @Override
    public void connected() {
        print("CONNECTED");
    }

    @Override
    public void paired() {
        print("PAIRED");
    }

    @Override
    public void disconnected(String reason) {
        print("DISCONNECTED " + reason);
    }

    @Override
    public String nameHost(String fingerprint) {
        return newHostName;
    }

    @Override
    public void bound(int conn, String fingerprint, boolean forwarding) {
        print("BIND fp=" + fingerprint + " forwarding=" + forwarding + conn(conn));
    }

    @Override
    public void signing(int conn, Destination destination) {
        if (destination.isSshsig()) {
            print("SIGN sshsig namespace=" + destination.namespace + conn(conn));
        } else {
            String through = destination.forwardedThrough.isEmpty()
                    ? ""
                    : " through=" + String.join(",", destination.forwardedThrough);
            print("SIGN userauth user=" + destination.user + " host=" + destination.host
                    + " fp=" + destination.fingerprint + through + conn(conn));
        }
    }

    @Override
    public void signed(int conn) {
        print("SIGNED" + conn(conn));
    }

    @Override
    public void refused(int conn, String reason) {
        print("REFUSE" + conn(conn) + " " + reason);
    }

    @Override
    public void cancelled(int conn) {
        print("CANCEL" + conn(conn));
    }

    private static String conn(int conn) {
        return " conn=" + Integer.toUnsignedString(conn);
    }

    @Override
    public synchronized String name(byte[] hostKey) {
        return hosts.get(Base64.getEncoder().encodeToString(hostKey));
    }

    @Override
    public synchronized void store(byte[] hostKey, String name) {
        String key = Base64.getEncoder().encodeToString(hostKey);
        hosts.put(key, name);
        try {
            Files.writeString(hostsFile, key + " " + name + "\n", StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
