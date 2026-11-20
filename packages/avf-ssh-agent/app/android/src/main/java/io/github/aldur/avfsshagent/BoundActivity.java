package io.github.aldur.avfsshagent;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.ServiceConnection;
import android.graphics.Insets;
import android.os.IBinder;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** A screen that shows the state of the agent service. */
abstract class BoundActivity extends Activity {
    /** Null while the screen is not visible. */
    protected AgentService service;

    private final Runnable listener = () -> {
        if (service != null) {
            render();
        }
    };

    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            service = ((AgentService.LocalBinder) binder).service();
            service.addListener(listener);
            render();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            service = null;
        }
    };

    /** Shows the state of the service. Runs on the main thread after each change. */
    abstract void render();

    @Override
    protected void onStart() {
        super.onStart();
        bindService(new Intent(this, AgentService.class), connection, BIND_AUTO_CREATE);
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (service != null) {
            service.removeListener(listener);
            service = null;
        }
        unbindService(connection);
    }

    /** Makes the content of the screen: a vertical list that scrolls. */
    protected LinearLayout content() {
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        int margin = dp(16);
        list.setPadding(margin, margin, margin, margin);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(list);
        // The window is as large as the display. Keep the content off the system bars and the
        // keyboard.
        scroll.setOnApplyWindowInsetsListener((view, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        setContentView(scroll);
        return list;
    }

    protected TextView heading(LinearLayout parent, String text) {
        TextView view = text(parent, text);
        view.setTextAppearance(android.R.style.TextAppearance_DeviceDefault_Medium);
        view.setPadding(0, dp(16), 0, dp(4));
        return view;
    }

    protected TextView text(LinearLayout parent, String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextIsSelectable(true);
        parent.addView(view);
        return view;
    }

    protected Button button(LinearLayout parent, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(view -> {
            if (service != null) {
                action.run();
            }
        });
        parent.addView(button);
        return button;
    }

    /** Adds a text field that keeps its content away from autofill and from the keyboard history. */
    protected EditText field(LinearLayout parent, String hint, int inputType) {
        EditText field = new EditText(this);
        field.setHint(hint);
        field.setInputType(inputType);
        field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        field.setImeOptions(EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING);
        // An attached YubiKey is a hardware keyboard. Then the system does not always show the
        // on-screen keyboard.
        field.setOnFocusChangeListener((view, focused) -> {
            WindowInsetsController controller = view.getWindowInsetsController();
            if (focused && controller != null) {
                controller.show(WindowInsets.Type.ime());
            }
        });
        parent.addView(field);
        return field;
    }

    /** Shows the text, or hides the view when there is no text. */
    protected static void show(TextView view, String text) {
        view.setText(text);
        view.setVisibility(text == null || text.isEmpty() ? View.GONE : View.VISIBLE);
    }

    protected int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
