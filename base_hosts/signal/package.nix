{ pkgs }:
# Signal catches key errors and retries SQL setup with a fixed key. Return
# before that recovery path can create a database.
pkgs.signal-desktop.overrideAttrs (old: {
  postPatch = old.postPatch + ''
    substituteInPlace app/main.main.ts --replace-fail \
      'sqlInitTimeStart = Date.now();' \
      'sqlInitTimeStart = Date.now();
      if (!safeStorage.isEncryptionAvailable() ||
          safeStorage.getSelectedStorageBackend() !== "gnome_libsecret" || OS.isFlatpak()) {
        const error = new Error("Signal appliance requires an unlocked GNOME keyring; plaintext key storage is forbidden");
        console.error(error.message);
        return { ok: false, error };
      }'
  '';
})
