{ pkgs }:
# Stop startup before Signal can retry SQL initialization with a fixed key.
pkgs.signal-desktop.overrideAttrs (old: {
  # Electron runs the JavaScript. Remove the Node store references from the
  # shebangs before ASAR calculates the file hashes.
  postBuild = ''
    grep -rlIZ '^#!${pkgs.nodejs_24}/bin/node$' node_modules \
      | xargs -0 -r sed -i '1s|^#!${pkgs.nodejs_24}/bin/node$|#!/usr/bin/env node|'
  ''
  + old.postBuild;
  disallowedReferences = (old.disallowedReferences or [ ]) ++ [ pkgs.nodejs_24 ];
  postPatch = old.postPatch + ''
    substituteInPlace app/main.main.ts --replace-fail \
      'sqlInitPromise = initializeSQL(userDataPath);' \
      'if (!safeStorage.isEncryptionAvailable() ||
          safeStorage.getSelectedStorageBackend() !== "gnome_libsecret" || OS.isFlatpak()) {
        const error = new Error("Signal appliance requires an unlocked GNOME keyring; plaintext key storage is forbidden");
        console.error(error.message);
        // Exit the startup callback to prevent database recovery.
        dialog.showMessageBoxSync({
          type: "error",
          message: "Secure keyring required",
          detail: error.message,
          buttons: ["Quit"],
          defaultId: 0,
          cancelId: 0,
        });
        app.exit(1);
        return;
      }
      sqlInitPromise = initializeSQL(userDataPath);'
  '';
})
