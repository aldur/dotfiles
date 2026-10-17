# Browser VM

Use the [build and VM instructions](../appliance/README.md). Start `firefox` in
the guest shell, or use the Firefox launcher entry.

Firefox keeps its normal sandbox, cookies and site storage. Extensions, Firefox
Sync, telemetry and saved passwords are disabled. Links open in the guest.

The Firefox profile in `~/.config/mozilla` is kept under `/state`.

QEMU clipboard integration is disabled. ChromeOS supplies its own clipboard integration.
