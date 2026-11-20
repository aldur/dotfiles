package io.github.aldur.avfsshagent;

import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputFilter;
import android.text.InputType;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.Arrays;

/** Asks for the PIN of the YubiKey or for the name of a new host key. */
public final class PromptActivity extends BoundActivity {
    private static final int MIN_PIN_LENGTH = 6;
    private static final int MAX_PIN_LENGTH = 8;
    private static final int MAX_NAME_LENGTH = 64;

    private LinearLayout content;
    private Prompt shown;
    private TextView message;
    private EditText input;
    private Button accept;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // The PIN must not show in screenshots and in the list of recent apps.
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        content = content();
    }

    @Override
    void render() {
        Prompt prompt = service.prompt();
        if (prompt == null) {
            // The answer is complete, or the agent cancelled the request.
            finish();
            return;
        }
        if (prompt != shown) {
            shown = prompt;
            content.removeAllViews();
            if (prompt.kind == Prompt.PIN) {
                buildPin();
            } else {
                buildHost();
            }
        }
        boolean waiting = prompt.waiting();
        show(message, waiting ? prompt.message() : "Wait...");
        input.setEnabled(waiting);
        accept.setEnabled(waiting);
    }

    private void buildPin() {
        heading(content, "PIN of the YubiKey");
        text(content, "For: " + shown.subject);
        message = text(content, "");
        input = field(content, "PIN", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        input.setFilters(new InputFilter[] {new InputFilter.LengthFilter(MAX_PIN_LENGTH)});

        // An attached YubiKey is a hardware keyboard. Then the system can hide the on-screen
        // keyboard. These buttons always work for a PIN of digits.
        GridLayout keys = new GridLayout(this);
        keys.setColumnCount(3);
        for (String label : new String[] {"1", "2", "3", "4", "5", "6", "7", "8", "9", "Delete", "0"}) {
            Button key = new Button(this);
            key.setText(label);
            key.setAllCaps(false);
            key.setOnClickListener(view -> {
                int length = input.length();
                if (label.length() == 1) {
                    input.append(label);
                } else if (length > 0) {
                    input.getText().delete(length - 1, length);
                }
            });
            keys.addView(key);
        }
        content.addView(keys);
        text(content, "For a PIN with letters, tap the PIN field. If no keyboard shows, turn on the on-screen"
                + " keyboard for physical keyboards in the system settings. Do not unplug the YubiKey.");

        accept = button(content, "OK", () -> {
            int length = input.length();
            if (length < MIN_PIN_LENGTH) {
                show(message, "A PIN has " + MIN_PIN_LENGTH + " to " + MAX_PIN_LENGTH + " characters.");
                return;
            }
            char[] pin = new char[length];
            input.getText().getChars(0, length, pin, 0);
            input.getText().clear();
            if (!shown.answer(pin)) {
                Arrays.fill(pin, '\0');
            }
            render();
        });
        button(content, "Cancel", () -> shown.answer(null));
    }

    private void buildHost() {
        heading(content, "New host key");
        text(content, "A connection uses a host key that has no name.");
        text(content, shown.subject).setTypeface(Typeface.MONOSPACE);
        text(content, "Compare this fingerprint with one from a source that you trust. Then give the host a"
                + " name, for example github.com. The agent shows this name for each later signature.");
        message = text(content, "");
        input = field(content, "Name of the host", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        input.setFilters(new InputFilter[] {new InputFilter.LengthFilter(MAX_NAME_LENGTH)});
        text(content, "No keyboard? Unplug the YubiKey for this step. This step does not use it.");
        // The focus opens the keyboard. Wait until the field is in the window.
        input.post(input::requestFocus);

        accept = button(content, "Accept", () -> {
            String name = AgentService.clean(input.getText().toString()).trim();
            if (name.isEmpty()) {
                show(message, "Type a name.");
                return;
            }
            shown.answer(name);
            render();
        });
        button(content, "Decline", () -> shown.answer(null));
    }
}
