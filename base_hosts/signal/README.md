# Signal VM

Use the [build and VM instructions](../appliance/README.md). QEMU starts Signal
automatically. On Baguette, use the Signal launcher entry or run `signal-desktop`.

On first use, enter and confirm a long, random keyring password. Save it in a
password manager.
Enter the same password after each VM restart. A blank password is rejected.
Link the desktop from Signal on your phone.

The keyring protects the database key. A small source patch makes Signal refuse
to create or open a database without GNOME keyring encryption. The build fails
if the patch no longer applies. There is no plaintext-key fallback.
[Electron documents the Linux storage fallback](https://www.electronjs.org/docs/latest/api/safe-storage).

The keyring does not encrypt the whole VM disk. Other profile files and cache
data can remain unencrypted. Use encrypted host storage and backups. Keep both
the Signal profile and `~/.local/share/keyrings` when you migrate state. A
password reset cannot recover a lost keyring password.
Stop the old VM before starting a restored copy of a linked desktop.

Signal runs with its Chromium sandbox and an additional systemd sandbox.
Its home view contains its profile and cache. Its session bus permits only the
Secret Service; the user manager and keyring control socket are hidden. Baguette also exposes its X11
authorization file. Host folder access, external link opening, notifications, port discovery and QEMU clipboard
support are disabled. Private network destinations are blocked. DNS is allowed
only through the local stub, which follows the host resolver configuration.
Signal requires an active firewall. A firewall failure powers off the VM.
These restrictions can prevent local proxies, attachment export and calls.
QEMU uses Cage and native Wayland as the session user. Closing Signal opens it
again. ChromeOS controls the Baguette display and clipboard. The guest account
can access Signal data while the keyring is unlocked.

The tests check the real app, password prompt, encrypted database, renderer
sandbox, network restrictions and persistence after restart. They also check
that the app rejects Electron's insecure storage backend. Account linking and
message delivery require a phone and a live Signal account; the tests do not
send messages.
