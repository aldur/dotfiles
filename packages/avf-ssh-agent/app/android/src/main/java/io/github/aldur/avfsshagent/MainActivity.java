package io.github.aldur.avfsshagent;

import android.Manifest;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import io.github.aldur.avfsshagent.core.SshKeys;
import java.util.Base64;
import java.util.Map;

/** The setup screen: state, pairing, the served key, the host names and the diagnostics. */
public final class MainActivity extends BoundActivity {
    private TextView state;
    private EditText pairingLine;
    private TextView pairingMessage;
    private TextView keyMessage;
    private TextView key;
    private LinearLayout hosts;
    private Map<String, String> shownHosts;
    private TextView diagnostics;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout content = content();

        heading(content, "AVF SSH agent");
        state = text(content, "");

        heading(content, "Pairing");
        text(content, "Run the pair command of the bridge in the Terminal. Paste the line that it prints.");
        pairingLine = field(content, "avf-ssh-pair:v1:...",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        button(content, "Paste", this::paste);
        button(content, "Pair", () -> {
            service.pair(pairingLine.getText().toString());
            // The line holds the one-time token. Do not keep it on the screen.
            pairingLine.getText().clear();
        });
        pairingMessage = text(content, "");

        heading(content, "Key");
        button(content, "Read the key from the YubiKey", () -> service.readKey());
        keyMessage = text(content, "");
        key = text(content, "");
        key.setTypeface(Typeface.MONOSPACE);
        button(content, "Copy", () -> copy("SSH public key", service.store().authorizedKey()));

        heading(content, "Hosts");
        hosts = new LinearLayout(this);
        hosts.setOrientation(LinearLayout.VERTICAL);
        content.addView(hosts);

        heading(content, "Diagnostics");
        button(content, "Self-test", () -> service.selfTest());
        button(content, "Copy diagnostics", () -> copy("Diagnostics", service.diagnostics()));
        diagnostics = text(content, "");
        diagnostics.setTypeface(Typeface.MONOSPACE);
        diagnostics.setTextSize(11);

        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 0);
        }
        startForegroundService(new Intent(this, AgentService.class));
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        // The system dropped the notification of the service that came before the permission.
        // A new start posts it again.
        startForegroundService(new Intent(this, AgentService.class));
    }

    @Override
    void render() {
        state.setText(service.stateText());
        show(pairingMessage, service.pairingMessage());
        show(keyMessage, service.keyMessage());
        String line = service.store().authorizedKey();
        key.setText(line == null ? "No key. Connect the YubiKey and read the key." : line);
        diagnostics.setText(service.diagnostics());

        Map<String, String> names = service.store().hosts();
        if (!names.equals(shownHosts)) {
            shownHosts = names;
            hosts.removeAllViews();
            if (names.isEmpty()) {
                text(hosts, "No names. The agent asks for a name at the first connection to a host.");
            }
            for (Map.Entry<String, String> host : names.entrySet()) {
                String fingerprint = SshKeys.fingerprint(Base64.getDecoder().decode(host.getKey()));
                text(hosts, AgentService.clean(host.getValue()) + "\n" + fingerprint);
                button(hosts, "Remove " + AgentService.clean(host.getValue()), () -> {
                    service.store().removeHost(host.getKey());
                    render();
                });
            }
        }
    }

    private void paste() {
        ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
        if (clip != null && clip.getItemCount() > 0) {
            pairingLine.setText(clip.getItemAt(0).coerceToText(this));
        }
    }

    private void copy(String label, String text) {
        if (text != null) {
            getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText(label, text));
        }
    }
}
