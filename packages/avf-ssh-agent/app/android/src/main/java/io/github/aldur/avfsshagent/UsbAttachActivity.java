package io.github.aldur.avfsshagent;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/** Starts the agent service when a YubiKey attaches. It shows nothing. */
public final class UsbAttachActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            startForegroundService(new Intent(this, AgentService.class));
        } catch (RuntimeException e) {
            Log.w(AgentService.TAG, "Cannot start the service for the YubiKey: " + e);
        }
        finish();
    }
}
