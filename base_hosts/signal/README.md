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

`/state` holds exactly the Signal profile (`~/.config/Signal`) and the keyrings
(`~/.local/share/keyrings`). The keyring does not encrypt the whole VM disk.
Other profile files can remain unencrypted. Use encrypted host storage and
backups. A password reset cannot recover a lost keyring password.
Stop the old VM before starting a restored copy of a linked desktop.

VMs are not upgraded and state is not migrated to a new image. Create a new VM
and link it from your phone again. The old desktop history is not transferred.

Signal runs with its Chromium sandbox and an additional systemd sandbox.
Its home view contains its profile and cache. Its session bus permits only the
Secret Service; the user manager and keyring control socket are hidden.
Host folder access, external link opening, notifications, port discovery and QEMU clipboard
support are disabled. Private network destinations are blocked. DNS is allowed
only through the local stub, which follows the host resolver configuration.
Signal requires an active firewall. A firewall failure powers off the VM.
These restrictions can prevent local proxies, attachment export and calls.
QEMU uses Cage and native Wayland as the session user. Closing Signal opens it
again. Baguette also uses Wayland. Check the ChromeOS window frame on the target
Chromebook. ChromeOS controls the Baguette display and clipboard. The guest account
can access Signal data while the keyring is unlocked.

The tests check the real app, password prompt, encrypted database, renderer
sandbox, network restrictions and persistence after restart. They also check
that the app rejects Electron's insecure storage backend. Account linking and
message delivery require a phone and a live Signal account; the tests do not
send messages.
