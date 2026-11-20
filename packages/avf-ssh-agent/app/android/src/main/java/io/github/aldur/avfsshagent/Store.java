package io.github.aldur.avfsshagent;

import android.content.Context;
import android.content.SharedPreferences;
import io.github.aldur.avfsshagent.core.HostStore;
import io.github.aldur.avfsshagent.core.SshKeys;
import java.util.Base64;
import java.util.Map;
import java.util.TreeMap;

/** The settings of the app: the pairing, the served key and the host names. */
final class Store implements HostStore {
    private static final String HOST = "host:";

    private final SharedPreferences prefs;

    Store(Context context) {
        prefs = context.getSharedPreferences("agent", Context.MODE_PRIVATE);
    }

    /** Returns the port of the bridge, or 0 when there is no pairing. */
    int port() {
        return prefs.getInt("port", 0);
    }

    /** Returns the pin of the bridge certificate, or null when there is no pairing. */
    String bridgePin() {
        return prefs.getString("bridgePin", null);
    }

    void setPairing(int port, String bridgePin) {
        prefs.edit().putInt("port", port).putString("bridgePin", bridgePin).apply();
    }

    /** Returns the SSH blob of the served key, or null. */
    byte[] keyBlob() {
        String blob = prefs.getString("keyBlob", null);
        return blob == null ? null : Base64.getDecoder().decode(blob);
    }

    String keyComment() {
        return prefs.getString("keyComment", "");
    }

    void setKey(byte[] blob, String comment) {
        prefs.edit().putString("keyBlob", encode(blob)).putString("keyComment", comment).apply();
    }

    /** Returns the served key as one line of an authorized_keys file, or null. */
    String authorizedKey() {
        String blob = prefs.getString("keyBlob", null);
        return blob == null ? null : SshKeys.P256 + " " + blob + " " + keyComment();
    }

    @Override
    public String name(byte[] hostKey) {
        return prefs.getString(HOST + encode(hostKey), null);
    }

    @Override
    public void store(byte[] hostKey, String name) {
        prefs.edit().putString(HOST + encode(hostKey), name).apply();
    }

    /** Returns the name of each host key. The map key is the host key blob in Base64. */
    Map<String, String> hosts() {
        Map<String, String> hosts = new TreeMap<>();
        for (Map.Entry<String, ?> entry : prefs.getAll().entrySet()) {
            if (entry.getKey().startsWith(HOST)) {
                hosts.put(entry.getKey().substring(HOST.length()), String.valueOf(entry.getValue()));
            }
        }
        return hosts;
    }

    void removeHost(String hostKeyBase64) {
        prefs.edit().remove(HOST + hostKeyBase64).apply();
    }

    private static String encode(byte[] blob) {
        return Base64.getEncoder().encodeToString(blob);
    }
}
