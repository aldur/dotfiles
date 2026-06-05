_: {
  # NOTE: This is not included in the default configuration, but is exposed as
  # a flake output.
  #
  # Rule-only: the kernel audit subsystem loads the rules below and emits
  # events to the kernel log, where journald captures them for the log pipeline
  # (journal → loki). The userspace auditd daemon is left off on purpose:
  # auditd writing /var/log/audit would only duplicate them on disk where
  # nothing consumes them.
  security = {
    auditd.enable = false;
    audit.enable = true;
    audit.rules = [
      "-a exit,always -F arch=b64 -S execve"
    ];
  };
}
