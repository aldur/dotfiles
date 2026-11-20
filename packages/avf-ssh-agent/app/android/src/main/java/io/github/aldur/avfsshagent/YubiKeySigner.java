package io.github.aldur.avfsshagent;

import android.os.SystemClock;
import com.yubico.yubikit.android.transport.usb.UsbYubiKeyDevice;
import com.yubico.yubikit.core.application.InvalidPinException;
import com.yubico.yubikit.core.smartcard.Apdu;
import com.yubico.yubikit.core.smartcard.ApduException;
import com.yubico.yubikit.core.smartcard.SW;
import com.yubico.yubikit.core.smartcard.SmartCardConnection;
import com.yubico.yubikit.core.smartcard.SmartCardProtocol;
import com.yubico.yubikit.piv.KeyType;
import com.yubico.yubikit.piv.PivSession;
import com.yubico.yubikit.piv.Slot;
import com.yubico.yubikit.piv.SlotMetadata;
import io.github.aldur.avfsshagent.core.SshKeys;
import java.io.Closeable;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.interfaces.ECPublicKey;
import java.util.Arrays;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Signs with the key in PIV slot 9a of a YubiKey on USB.
 *
 * <p>One smart card connection stays open while the YubiKey is attached, because the card keeps
 * the PIN state only for that connection.
 */
final class YubiKeySigner {
    /** The public key of slot 9a. */
    static final class SlotKey {
        final byte[] blob;
        /** 0 when the YubiKey does not give its serial number. */
        final int serial;

        SlotKey(byte[] blob, int serial) {
            this.blob = blob;
            this.serial = serial;
        }
    }

    // After an attach, the system can give the USB permission without a dialog. Do not ask
    // for it before this time.
    private static final long PERMISSION_GRACE_MILLIS = 2_000;

    private final AgentService service;
    // All card commands run on this thread. A command can block until the touch.
    private final ExecutorService card = Executors.newSingleThreadExecutor();
    private final ReentrantLock signLock = new ReentrantLock();

    // The lock of this object guards the fields below. Do not call a synchronized method of the
    // service while you hold it.
    private UsbYubiKeyDevice device;
    private long attachedAt;
    private boolean permissionAsked;
    private String openProblem;
    private SmartCardConnection connection;
    private PivSession piv;
    private byte[] slotKey;
    private String slotProblem;
    private int serial;
    private boolean pinVerified;
    /** The thread that is in {@link #sign}. */
    private Thread signing;
    private boolean userCancelled;

    YubiKeySigner(AgentService service) {
        this.service = service;
    }

    /** A YubiKey is attached. */
    void attached(UsbYubiKeyDevice attached) {
        UsbYubiKeyDevice old;
        synchronized (this) {
            old = device;
        }
        // The detach event of the old YubiKey can come late. The new YubiKey replaces it.
        detached(old);
        synchronized (this) {
            device = attached;
            attachedAt = SystemClock.elapsedRealtime();
            permissionAsked = false;
            notifyAll();
        }
        service.log("YubiKey attached");
        attached.setOnClosed(() -> detached(attached));
        card.execute(() -> open(false));
        service.changed();
    }

    private void detached(UsbYubiKeyDevice gone) {
        synchronized (this) {
            if (gone == null || device != gone) {
                return;
            }
            device = null;
            openProblem = null;
            dropSession();
            notifyAll();
        }
        service.log("YubiKey detached");
        service.changed();
    }

    /** Forgets the PIV session. Call with the lock of this object. */
    private void dropSession() {
        PivSession session = piv;
        piv = null;
        connection = null;
        slotKey = null;
        slotProblem = null;
        pinVerified = false;
        if (session != null) {
            // The card thread closes it after the command that is in progress.
            card.execute(() -> closeQuietly(session));
        }
    }

    /** A card command failed. The next request opens the YubiKey again. */
    private synchronized void broken(PivSession session, IOException e) {
        if (piv == session) {
            service.log("The connection to the YubiKey failed: " + e);
            dropSession();
            notifyAll();
            service.changed();
        }
    }

    /** The user cancelled the request that waits for the YubiKey. */
    synchronized void cancel() {
        if (signing != null) {
            userCancelled = true;
            signing.interrupt();
        }
    }

    /** Tries to open the attached YubiKey again, for example after a change of the USB permission. */
    void poke() {
        card.execute(() -> open(false));
    }

    void shutdown() {
        card.shutdownNow();
        synchronized (this) {
            closeQuietly(piv);
            piv = null;
            connection = null;
            device = null;
            notifyAll();
        }
    }

    /** Returns one line for the state screen. */
    synchronized String status() {
        if (device == null) {
            return "not attached";
        }
        if (piv == null) {
            return "attached, not open" + (openProblem == null ? "" : " (" + openProblem + ")");
        }
        String number = serial == 0 ? "" : " #" + serial;
        if (slotKey == null) {
            return "attached" + number + ", " + slotProblem;
        }
        return "attached" + number + ", slot 9a " + SshKeys.fingerprint(slotKey)
                + (pinVerified ? ", PIN verified" : ", PIN not verified");
    }

    /** Waits for a YubiKey and returns the public key of its slot 9a. */
    SlotKey readKey(long timeoutMillis) throws Exception {
        await(null, "Read the key", timeoutMillis);
        synchronized (this) {
            if (slotKey == null) {
                throw new IOException(slotProblem == null ? "The YubiKey is not attached" : slotProblem);
            }
            return new SlotKey(slotKey, serial);
        }
    }

    /**
     * Returns the DER ECDSA signature of SHA-256({@code data}) by the key {@code keyBlob}.
     *
     * <p>Waits for the YubiKey, the PIN and the touch. An interrupt ends each wait.
     *
     * @param destination the text that tells the user what the signature is for
     * @param timeoutMillis the longest wait for the YubiKey, or 0 for no limit
     */
    byte[] sign(byte[] keyBlob, byte[] data, String destination, long timeoutMillis) throws Exception {
        signLock.lockInterruptibly();
        synchronized (this) {
            signing = Thread.currentThread();
            userCancelled = false;
        }
        try {
            PivSession session = await(keyBlob, destination, timeoutMillis);
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(data);
            String message = "";
            for (int attempt = 0; ; attempt++) {
                if (!pinVerified(session)) {
                    verifyPin(session, destination, message);
                }
                service.notice("Touch your YubiKey: " + destination, true);
                try {
                    return onCard(session,
                            () -> session.rawSignOrDecrypt(Slot.AUTHENTICATION, KeyType.ECCP256, digest));
                } catch (ApduException e) {
                    if (e.getSw() != SW.SECURITY_CONDITION_NOT_SATISFIED) {
                        throw e;
                    }
                    // The card gives this status for a touch that did not come, and for a PIN
                    // that is not verified.
                    if (onCard(session, () -> pinVerifiedOnCard(session))) {
                        throw new IOException("No touch of the YubiKey in time");
                    }
                    if (attempt > 0) {
                        throw e;
                    }
                    service.log("The YubiKey needs the PIN again");
                    setPinVerified(session, false);
                    message = "The YubiKey needs the PIN again.";
                } finally {
                    service.notice(null, false);
                }
            }
        } catch (InterruptedException e) {
            synchronized (this) {
                if (userCancelled) {
                    throw new IOException("The user cancelled the request");
                }
            }
            throw e;
        } finally {
            synchronized (this) {
                signing = null;
            }
            signLock.unlock();
        }
    }

    /**
     * Asks the card if the PIN is verified, with a VERIFY command that has no PIN. This command
     * does not use a PIN retry. Runs on the card thread.
     */
    private boolean pinVerifiedOnCard(PivSession session) throws IOException {
        SmartCardConnection open;
        synchronized (this) {
            if (piv != session) {
                throw new IOException("The YubiKey is not attached");
            }
            open = connection;
        }
        try {
            // Do not close this protocol object: that closes the connection of the PIV session.
            new SmartCardProtocol(open).sendAndReceive(new Apdu(0, 0x20, 0, 0x80, null));
            return true;
        } catch (ApduException e) {
            return false;
        }
    }

    /**
     * Waits until a YubiKey is open and, if {@code wantKey} is not null, holds that key in slot
     * 9a. While it waits, a notification tells the user what to do.
     */
    private synchronized PivSession await(byte[] wantKey, String purpose, long timeoutMillis)
            throws InterruptedException, TimeoutException {
        long deadline = timeoutMillis == 0 ? Long.MAX_VALUE : SystemClock.elapsedRealtime() + timeoutMillis;
        String shown = null;
        try {
            while (true) {
                if (piv != null && (wantKey == null || Arrays.equals(wantKey, slotKey))) {
                    return piv;
                }
                String text;
                if (device == null) {
                    text = "Connect your YubiKey";
                } else if (piv == null) {
                    text = openProblem == null ? "Opening the YubiKey" : openProblem;
                } else {
                    text = slotKey == null ? slotProblem : "Wrong YubiKey";
                }
                if (!text.equals(shown)) {
                    shown = text;
                    service.log(text + " (" + purpose + ")");
                    // Only a sign request has a cancel. The other waits end at their timeout.
                    service.notice(text + ": " + purpose, wantKey != null);
                }
                long left = deadline - SystemClock.elapsedRealtime();
                if (left <= 0) {
                    throw new TimeoutException(text);
                }
                if (device != null && piv == null) {
                    card.execute(() -> open(true));
                }
                wait(Math.min(left, 1_000));
            }
        } finally {
            if (shown != null) {
                service.notice(null, false);
            }
        }
    }

    /** Asks for the PIN until the card accepts it. Fails when the PIN is blocked. */
    private void verifyPin(PivSession session, String destination, String message) throws Exception {
        Prompt prompt = service.openPrompt(Prompt.PIN, destination);
        try {
            while (true) {
                int retries = onCard(session, session::getPinAttempts);
                if (retries == 0) {
                    throw new IOException("The PIN of the YubiKey is blocked");
                }
                char[] pin = (char[]) service.ask(prompt, (message + " " + retries + " PIN retries left.").trim());
                if (pin == null) {
                    throw new IOException("The user cancelled the PIN entry");
                }
                try {
                    onCard(session, () -> {
                        session.verifyPin(pin);
                        return null;
                    });
                    setPinVerified(session, true);
                    service.log("PIN accepted");
                    return;
                } catch (InvalidPinException e) {
                    service.log("PIN rejected, " + e.getAttemptsRemaining() + " retries left");
                    message = "Wrong PIN.";
                } catch (IllegalArgumentException e) {
                    // YubiKit refuses a PIN of more than 8 bytes before it sends a command.
                    service.log("PIN not sent: " + e.getMessage());
                    message = "The PIN is too long.";
                } finally {
                    Arrays.fill(pin, '\0');
                }
            }
        } finally {
            service.closePrompt(prompt);
        }
    }

    private synchronized boolean pinVerified(PivSession session) {
        return piv == session && pinVerified;
    }

    private synchronized void setPinVerified(PivSession session, boolean verified) {
        if (piv == session) {
            pinVerified = verified;
        }
        service.changed();
    }

    /**
     * Runs a card command on the card thread. After an interrupt, the call returns only when the
     * command is not in progress: a later touch must not complete a cancelled request.
     */
    private <T> T onCard(PivSession session, Callable<T> command) throws Exception {
        Future<T> result = card.submit(command);
        try {
            return result.get();
        } catch (ExecutionException e) {
            if (e.getCause() instanceof IOException) {
                broken(session, (IOException) e.getCause());
            }
            if (e.getCause() instanceof Exception) {
                throw (Exception) e.getCause();
            }
            throw e;
        } catch (InterruptedException e) {
            // This removes a command that waits. It does not stop a command that runs.
            result.cancel(false);
            awaitCardIdle();
            throw e;
        }
    }

    /** Waits for the end of the card command that is in progress. The touch timeout of the card limits the wait. */
    private void awaitCardIdle() {
        Future<?> idle = card.submit(() -> { });
        boolean told = false;
        while (true) {
            try {
                idle.get(200, TimeUnit.MILLISECONDS);
                break;
            } catch (TimeoutException e) {
                if (!told) {
                    told = true;
                    service.log("Request cancelled while the YubiKey waits for a touch");
                    service.notice("Request cancelled. Do not touch the YubiKey.", false);
                }
            } catch (InterruptedException e) {
                // A second cancel changes nothing.
            } catch (ExecutionException e) {
                break;
            }
        }
        if (told) {
            service.notice(null, false);
        }
    }

    /**
     * Opens the attached YubiKey and reads slot 9a. Runs on the card thread.
     *
     * @param mayAsk a request waits for the YubiKey, thus a permission dialog is acceptable
     */
    private void open(boolean mayAsk) {
        UsbYubiKeyDevice opening;
        synchronized (this) {
            opening = device;
            if (opening == null || piv != null) {
                return;
            }
            if (!opening.hasPermission()) {
                boolean ask = mayAsk && !permissionAsked
                        && SystemClock.elapsedRealtime() - attachedAt > PERMISSION_GRACE_MILLIS;
                if (ask) {
                    permissionAsked = true;
                    service.requestUsbPermission(opening.getUsbDevice());
                }
                setOpenProblem("Allow the USB access to the YubiKey");
                return;
            }
        }

        SmartCardConnection opened;
        PivSession session;
        try {
            opened = opening.openConnection(SmartCardConnection.class);
            try {
                session = new PivSession(opened);
            } catch (Exception e) {
                closeQuietly(opened);
                throw e;
            }
        } catch (Exception e) {
            synchronized (this) {
                setOpenProblem("Cannot open the YubiKey: " + e);
            }
            return;
        }

        int number = 0;
        try {
            number = session.getSerialNumber();
        } catch (Exception e) {
            service.log("The YubiKey does not give its serial number: " + e);
        }
        byte[] key = null;
        String problem = null;
        try {
            key = SshKeys.p256Blob(readSlot(session));
        } catch (Exception e) {
            problem = "slot 9a holds no ECC P-256 key (" + e + ")";
        }

        synchronized (this) {
            if (device != opening) {
                closeQuietly(session);
                return;
            }
            connection = opened;
            piv = session;
            slotKey = key;
            slotProblem = problem;
            serial = number;
            pinVerified = false;
            openProblem = null;
            notifyAll();
        }
        service.log("YubiKey open: serial " + number + ", PIV " + session.getVersion() + ", "
                + (key == null ? problem : "slot 9a " + SshKeys.fingerprint(key)));
        service.changed();
    }

    private static ECPublicKey readSlot(PivSession session) throws Exception {
        PublicKey key;
        if (session.supports(PivSession.FEATURE_METADATA)) {
            SlotMetadata metadata = session.getSlotMetadata(Slot.AUTHENTICATION);
            if (metadata.getKeyType() != KeyType.ECCP256) {
                throw new IOException("the key type is " + metadata.getKeyType());
            }
            key = metadata.getPublicKeyValues().toPublicKey();
        } else {
            key = session.getCertificate(Slot.AUTHENTICATION).getPublicKey();
        }
        if (!(key instanceof ECPublicKey)) {
            throw new IOException("the key type is " + key.getAlgorithm());
        }
        return (ECPublicKey) key;
    }

    /** Call with the lock of this object. */
    private void setOpenProblem(String problem) {
        if (!problem.equals(openProblem)) {
            openProblem = problem;
            service.log(problem);
            service.changed();
            notifyAll();
        }
    }

    private static void closeQuietly(Closeable closeable) {
        try {
            if (closeable != null) {
                closeable.close();
            }
        } catch (IOException | RuntimeException e) {
            // The YubiKey is gone.
        }
    }
}
