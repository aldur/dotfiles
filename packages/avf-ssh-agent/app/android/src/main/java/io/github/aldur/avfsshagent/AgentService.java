package io.github.aldur.avfsshagent;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import com.yubico.yubikit.android.transport.usb.UsbConfiguration;
import com.yubico.yubikit.android.transport.usb.UsbYubiKeyManager;
import io.github.aldur.avfsshagent.core.Agent;
import io.github.aldur.avfsshagent.core.Client;
import io.github.aldur.avfsshagent.core.Destination;
import io.github.aldur.avfsshagent.core.Pairing;
import io.github.aldur.avfsshagent.core.SshKeys;
import io.github.aldur.avfsshagent.core.Ui;
import java.nio.charset.StandardCharsets;
import java.text.DateFormat;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Owns all that lives longer than a screen: the connection to the bridge, the YubiKey, the
 * prompts and the log.
 */
public final class AgentService extends Service implements Ui, Client.Listener {
    static final String TAG = "AvfSshAgent";

    private static final String ACTION_CANCEL = "io.github.aldur.avfsshagent.CANCEL";
    private static final String CHANNEL_STATUS = "status";
    private static final String CHANNEL_ALERT = "alert";
    private static final int NOTE_STATUS = 1;
    private static final int NOTE_PROMPT = 2;
    private static final int NOTE_NOTICE = 3;
    private static final int NOTE_REFUSED = 4;

    private static final int LOG_LINES = 200;
    private static final long TASK_TIMEOUT_MILLIS = 60_000;
    private static final byte[] SELF_TEST_MESSAGE =
            "avf-ssh-agent self-test".getBytes(StandardCharsets.US_ASCII);

    final class LocalBinder extends Binder {
        AgentService service() {
            return AgentService.this;
        }
    }

    private final Handler main = new Handler(Looper.getMainLooper());
    private final List<Runnable> listeners = new ArrayList<>();
    private final Runnable notifyListeners = () -> {
        for (Runnable listener : new ArrayList<>(listeners)) {
            listener.run();
        }
    };
    private final ArrayDeque<String> log = new ArrayDeque<>();
    private final ReentrantLock promptLock = new ReentrantLock();

    private Store store;
    private NotificationManager notifications;
    private YubiKeySigner signer;
    private UsbYubiKeyManager usb;

    private volatile Prompt prompt;
    // The core calls Ui.signing and then the signer on the same thread.
    private final ThreadLocal<String> destination = new ThreadLocal<>();

    // The lock of this object guards the fields below.
    private Identity identity;
    private String identityProblem = "not ready";
    private String hostKeyTest = "not complete";
    private Client client;
    private Thread clientThread;
    private Pairing pendingPairing;
    private String pairingMessage = "";
    private String keyMessage = "";
    private boolean connected;
    private long connectedSince;
    private int connections;
    private String lastDisconnect;
    private int sameDisconnects;
    private boolean foreground;
    private String shownStatus;
    private Thread task;

    @Override
    public void onCreate() {
        super.onCreate();
        store = new Store(this);
        signer = new YubiKeySigner(this);
        notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(
                new NotificationChannel(CHANNEL_STATUS, "Connection state", NotificationManager.IMPORTANCE_LOW));
        notifications.createNotificationChannel(new NotificationChannel(
                CHANNEL_ALERT, "PIN, touch and host key requests", NotificationManager.IMPORTANCE_HIGH));

        log("Service start");
        foreground();
        try {
            usb = new UsbYubiKeyManager(this);
            // The signer asks for the USB permission only when a request needs the YubiKey.
            usb.enable(new UsbConfiguration().handlePermissions(false), signer::attached);
        } catch (RuntimeException e) {
            log("Cannot listen for the YubiKey: " + e);
        }
        new Thread(this::prepare, "avf-ssh-agent-prepare").start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        foreground();
        if (intent != null && ACTION_CANCEL.equals(intent.getAction())) {
            cancelRequest();
        } else {
            // A start can follow a change of the USB permission.
            signer.poke();
        }
        return START_STICKY;
    }

    /**
     * Makes this a foreground service. Each start must do this: the system stops an app that
     * does not answer startForegroundService.
     */
    private void foreground() {
        synchronized (this) {
            foreground = true;
            shownStatus = statusText();
        }
        try {
            startForeground(NOTE_STATUS, statusNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } catch (RuntimeException e) {
            synchronized (this) {
                foreground = false;
            }
            log("Not a foreground service: " + e);
            update();
        }
    }

    /** The user selected Cancel on a notification. */
    private void cancelRequest() {
        log("The user cancelled the request");
        Prompt open = prompt;
        if (open == null || !open.answer(null)) {
            signer.cancel();
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return new LocalBinder();
    }

    @Override
    public void onDestroy() {
        log("Service stop");
        synchronized (this) {
            stopClient();
        }
        if (usb != null) {
            usb.disable();
        }
        signer.shutdown();
        super.onDestroy();
    }

    /** Loads the TLS key and connects. The Keystore and the self-test can be slow. */
    private void prepare() {
        Identity loaded = null;
        String problem = null;
        try {
            loaded = Identity.load();
            log("TLS key ready, pin " + loaded.pin());
        } catch (Exception e) {
            problem = e.toString();
            log("Cannot load the TLS key: " + e);
        }
        synchronized (this) {
            identity = loaded;
            identityProblem = problem;
            connect(null);
        }
        String result = SshKeys.selfTest().toString();
        log("Host key verification: " + result);
        synchronized (this) {
            hostKeyTest = result;
        }
        changed();
    }

    // The screens. Call these methods on the main thread.

    Store store() {
        return store;
    }

    Prompt prompt() {
        return prompt;
    }

    void addListener(Runnable listener) {
        listeners.add(listener);
    }

    void removeListener(Runnable listener) {
        listeners.remove(listener);
    }

    synchronized String pairingMessage() {
        return pairingMessage;
    }

    synchronized String keyMessage() {
        return keyMessage;
    }

    /** Starts the pairing with a line that the bridge printed. */
    synchronized void pair(String line) {
        Pairing pairing;
        try {
            pairing = Pairing.parse(line);
        } catch (IllegalArgumentException e) {
            pairingMessage = "This is not a pairing line. Copy the full line that the pair command prints.";
            changed();
            return;
        }
        if (identity == null) {
            pairingMessage = "The TLS key is not available: " + identityProblem;
        } else if (store.keyBlob() == null) {
            pairingMessage = "Read the key from the YubiKey first. Then run the pair command again.";
        } else {
            pairingMessage = "Pairing on port " + pairing.port + "...";
            log("Pairing with the bridge on port " + pairing.port);
            connect(pairing);
        }
        changed();
    }

    /** Reads slot 9a of the YubiKey and stores its public key as the served key. */
    void readKey() {
        runTask(() -> {
            setKeyMessage("Waiting for the YubiKey...");
            try {
                YubiKeySigner.SlotKey key = signer.readKey(TASK_TIMEOUT_MILLIS);
                String number = key.serial == 0 ? "" : " #" + key.serial;
                store.setKey(key.blob, "YubiKey" + number + " PIV Slot 9a");
                log("Stored the key " + SshKeys.fingerprint(key.blob));
                setKeyMessage("");
                synchronized (this) {
                    connect(null);
                }
            } catch (Exception e) {
                log("Cannot read the key: " + e);
                setKeyMessage("Cannot read the key: " + e.getMessage());
            }
        });
    }

    /** Signs a fixed message with the YubiKey and verifies the signature with the stored key. */
    void selfTest() {
        runTask(() -> {
            log("Self-test: start");
            byte[] key = store.keyBlob();
            if (key == null) {
                log("Self-test: FAILED: no key is stored");
                return;
            }
            try {
                byte[] signature = signer.sign(key, SELF_TEST_MESSAGE, "Self-test", TASK_TIMEOUT_MILLIS);
                log("Self-test: the YubiKey made a signature of " + signature.length + " bytes");
                SshKeys.verifyServed(key, SELF_TEST_MESSAGE, signature);
                log("Self-test: PASSED: the signature is correct for the stored key");
            } catch (InterruptedException e) {
                log("Self-test: FAILED: no answer in " + 2 * TASK_TIMEOUT_MILLIS / 1000 + " seconds");
            } catch (Exception e) {
                log("Self-test: FAILED: " + e);
            }
        });
    }

    private synchronized void runTask(Runnable work) {
        if (task != null && task.isAlive()) {
            log("An operation with the YubiKey is in progress. Wait for its end.");
            return;
        }
        Thread thread = new Thread(work, "avf-ssh-agent-task");
        task = thread;
        thread.start();
        // No core request cancels this work. Thus limit all its waits.
        main.postDelayed(thread::interrupt, 2 * TASK_TIMEOUT_MILLIS);
    }

    private void setKeyMessage(String message) {
        synchronized (this) {
            keyMessage = message;
        }
        changed();
    }

    /** Returns the state for the main screen and for the diagnostics. */
    synchronized String stateText() {
        StringBuilder text = new StringBuilder();
        text.append("Pairing: ")
                .append(store.bridgePin() == null ? "not paired" : "paired, bridge port " + store.port())
                .append("\nKey: ")
                .append(store.keyBlob() == null ? "none" : clean(store.keyComment()))
                .append("\nConnection: ");
        if (connected) {
            text.append("connected since ").append(DateFormat.getTimeInstance().format(new Date(connectedSince)));
        } else if (client == null) {
            text.append("off");
        } else {
            text.append("waiting for the Terminal");
        }
        if (lastDisconnect != null) {
            text.append("\nLast disconnect: ").append(lastDisconnect);
            if (sameDisconnects > 1) {
                text.append(" (").append(sameDisconnects).append(" times)");
            }
        }
        text.append("\nReconnects: ").append(Math.max(0, connections - 1));
        text.append("\nYubiKey: ").append(signer.status());
        return text.toString();
    }

    /** Returns the text of the diagnostics. It holds no PIN, no pairing token and no signed data. */
    String diagnostics() {
        StringBuilder text = new StringBuilder();
        try {
            PackageInfo info =
                    getPackageManager().getPackageInfo(getPackageName(), PackageManager.PackageInfoFlags.of(0));
            text.append("Version: ").append(info.versionName).append(" (").append(info.getLongVersionCode())
                    .append(")\n");
        } catch (PackageManager.NameNotFoundException e) {
            text.append("Version: ").append(e).append('\n');
        }
        text.append("Android: ").append(Build.VERSION.RELEASE).append(", API ").append(Build.VERSION.SDK_INT)
                .append(", ").append(Build.MODEL).append('\n');
        text.append(stateText()).append('\n');
        synchronized (this) {
            text.append("TLS pin of the app: ")
                    .append(identity == null ? identityProblem : identity.pin())
                    .append('\n');
            text.append("Host key verification: ").append(hostKeyTest).append('\n');
        }
        text.append("Notifications: ").append(notifications.areNotificationsEnabled() ? "permitted" : "BLOCKED")
                .append('\n');
        boolean unrestricted = getSystemService(PowerManager.class).isIgnoringBatteryOptimizations(getPackageName());
        text.append("Battery optimization: ").append(unrestricted ? "off" : "ON").append('\n');
        text.append("Log:\n");
        synchronized (log) {
            int skip = Math.max(0, log.size() - 50);
            for (String line : log) {
                if (skip-- <= 0) {
                    text.append(line).append('\n');
                }
            }
        }
        return text.toString();
    }

    // The connection to the bridge.

    /**
     * Starts the client again. Call with the lock of this object.
     *
     * @param pairing a new pairing to try, or null for the stored pairing
     */
    private void connect(Pairing pairing) {
        stopClient();
        pendingPairing = pairing;
        byte[] key = store.keyBlob();
        int port = pairing == null ? store.port() : pairing.port;
        String bridgePin = pairing == null ? store.bridgePin() : pairing.pin;
        if (identity != null && key != null && bridgePin != null) {
            Agent agent = new Agent(key, store.keyComment(), data -> signer.sign(key, data, destination.get(), 0),
                    store, this);
            client = new Client(port, bridgePin, pairing == null ? null : pairing.token,
                    identity.keyManagers(), agent, this);
            clientThread = new Thread(client::run, "avf-ssh-agent-client");
            clientThread.start();
        }
        update();
    }

    /** Call with the lock of this object. */
    private void stopClient() {
        if (client != null) {
            client.stop();
            clientThread.interrupt();
            client = null;
            clientThread = null;
        }
        connected = false;
    }

    /** Returns true when the calling thread belongs to a client that is not in use. */
    private boolean staleClient() {
        return Thread.currentThread() != clientThread;
    }

    @Override
    public void connected() {
        synchronized (this) {
            if (staleClient()) {
                return;
            }
            connected = true;
            connectedSince = System.currentTimeMillis();
            connections++;
        }
        log("Connected to the bridge");
        update();
    }

    @Override
    public void paired() {
        synchronized (this) {
            if (staleClient() || pendingPairing == null) {
                return;
            }
            store.setPairing(pendingPairing.port, pendingPairing.pin);
            pendingPairing = null;
            pairingMessage = "Paired.";
        }
        log("The bridge accepted the pairing");
        update();
    }

    @Override
    public void disconnected(String reason) {
        synchronized (this) {
            if (staleClient()) {
                return;
            }
            // While the Terminal does not run, the same failure comes again every few seconds.
            boolean repeat = !connected && reason.equals(lastDisconnect);
            sameDisconnects = repeat ? sameDisconnects + 1 : 1;
            connected = false;
            lastDisconnect = reason;
            if (!repeat) {
                log("No connection to the bridge: " + reason);
            }
            if (pendingPairing != null) {
                pairingMessage = "Pairing failed: " + reason + ". Make sure that the port is on in the Terminal"
                        + " settings (Port control). Then run the pair command again: a pairing line is"
                        + " good for 5 minutes and for one use.";
                log("Pairing failed");
                connect(null);
                return;
            }
        }
        update();
    }

    // The agent events. They come from core threads.

    @Override
    public String nameHost(String fingerprint) throws InterruptedException {
        log("Unknown host key " + fingerprint + ": asking for a name");
        Prompt hostPrompt = openPrompt(Prompt.HOST, fingerprint);
        try {
            String name = (String) ask(hostPrompt, "");
            log(name == null ? "The user declined the host key" : "The user named the host key: " + name);
            return name;
        } finally {
            closePrompt(hostPrompt);
        }
    }

    @Override
    public void bound(int conn, String fingerprint, boolean forwarding) {
        log("Session bind, conn " + Integer.toUnsignedString(conn) + ", host key " + fingerprint
                + (forwarding ? ", forwarding" : ""));
    }

    @Override
    public void signing(int conn, Destination signDestination) {
        destination.set(clean(signDestination.toString()));
        log("Sign request, conn " + Integer.toUnsignedString(conn) + ": " + destination.get());
    }

    @Override
    public void signed(int conn) {
        log("Signed, conn " + Integer.toUnsignedString(conn));
    }

    @Override
    public void refused(int conn, String reason) {
        log("Refused, conn " + Integer.toUnsignedString(conn) + ": " + reason);
        notifications.notify(NOTE_REFUSED, alert("Request refused", clean(reason)).setTimeoutAfter(15_000).build());
    }

    @Override
    public void cancelled(int conn) {
        log("Cancelled, conn " + Integer.toUnsignedString(conn));
    }

    // What the signer and the agent events use. These methods do not take the lock of this object.

    /** Adds a line to the log. Never pass a PIN, a pairing token or signed data. */
    void log(String line) {
        String text = clean(line);
        Log.i(TAG, text);
        synchronized (log) {
            if (log.size() == LOG_LINES) {
                log.removeFirst();
            }
            log.addLast(LocalTime.now().truncatedTo(ChronoUnit.SECONDS) + " " + text);
        }
        changed();
    }

    /** Tells the screens that the state changed. */
    void changed() {
        main.removeCallbacks(notifyListeners);
        main.post(notifyListeners);
    }

    /**
     * Shows what the user must do with the YubiKey. Null removes the notification.
     *
     * @param canCancel the notification has a Cancel action for the request in progress
     */
    void notice(String text, boolean canCancel) {
        if (text == null) {
            notifications.cancel(NOTE_NOTICE);
            return;
        }
        Notification.Builder notice = alert("YubiKey", text);
        if (canCancel) {
            notice.addAction(cancelAction());
        }
        notifications.notify(NOTE_NOTICE, notice.build());
    }

    private Notification.Action cancelAction() {
        PendingIntent cancel = PendingIntent.getService(this, 0,
                new Intent(this, AgentService.class).setAction(ACTION_CANCEL), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Action.Builder(null, "Cancel", cancel).build();
    }

    /** Starts a prompt. Only one prompt is open at a time: the call waits for its turn. */
    Prompt openPrompt(int kind, String subject) throws InterruptedException {
        promptLock.lockInterruptibly();
        prompt = new Prompt(kind, subject);
        return prompt;
    }

    /** Shows the prompt and waits for the answer. Null is a refusal of the user. */
    Object ask(Prompt open, String message) throws InterruptedException {
        open.begin(message);
        Intent screen = new Intent(this, PromptActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        String title = open.kind == Prompt.PIN ? "PIN needed: " + open.subject : "New host key: " + open.subject;
        notifications.notify(NOTE_PROMPT, alert(title, (message + " Tap to answer.").trim())
                .setContentIntent(PendingIntent.getActivity(this, 0, screen, PendingIntent.FLAG_IMMUTABLE))
                .addAction(cancelAction())
                .build());
        try {
            // The system permits this only while a screen of the app is visible. If not, the
            // user opens the screen from the notification.
            startActivity(screen);
        } catch (RuntimeException e) {
            log("Cannot open the prompt screen: " + e);
        }
        changed();
        return open.await();
    }

    void closePrompt(Prompt open) {
        prompt = null;
        notifications.cancel(NOTE_PROMPT);
        promptLock.unlock();
        changed();
    }

    /** Asks the user for the USB permission. The answer starts this service again. */
    void requestUsbPermission(UsbDevice device) {
        log("Asking for the USB permission");
        PendingIntent result = PendingIntent.getService(
                this, 0, new Intent(this, AgentService.class), PendingIntent.FLAG_IMMUTABLE);
        getSystemService(UsbManager.class).requestPermission(device, result);
    }

    /** Updates the persistent notification, if its text changed, and the screens. */
    private void update() {
        synchronized (this) {
            if (!statusText().equals(shownStatus)) {
                shownStatus = statusText();
                notifications.notify(NOTE_STATUS, statusNotification());
            }
        }
        changed();
    }

    private synchronized String statusText() {
        if (!foreground) {
            return "Open the app: the system can stop the agent";
        }
        if (store.bridgePin() == null) {
            return "Not paired";
        }
        return connected ? "Connected to the Terminal" : "Waiting for the Terminal";
    }

    private Notification statusNotification() {
        PendingIntent open = PendingIntent.getActivity(
                this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL_STATUS)
                .setSmallIcon(R.drawable.ic_key)
                .setContentTitle(statusText())
                .setContentIntent(open)
                .setOngoing(true)
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .build();
    }

    private Notification.Builder alert(String title, String text) {
        return new Notification.Builder(this, CHANNEL_ALERT)
                .setSmallIcon(R.drawable.ic_key)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text));
    }

    /** Replaces the characters that can change how a line shows. The guest controls some texts. */
    static String clean(String text) {
        return text.replaceAll("[\\p{Cc}\\p{Cf}]", " ");
    }
}
