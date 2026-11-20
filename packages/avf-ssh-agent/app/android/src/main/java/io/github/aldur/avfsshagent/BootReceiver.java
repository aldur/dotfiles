package io.github.aldur.avfsshagent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** Starts the agent service after the boot. */
public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        try {
            context.startForegroundService(new Intent(context, AgentService.class));
        } catch (RuntimeException e) {
            Log.w(AgentService.TAG, "Cannot start the service after the boot: " + e);
        }
    }
}
