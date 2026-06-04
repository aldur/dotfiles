_: {
  # NOTE: This is not included in the default configuration,
  # but is exposed as a flake output.
  #
  # Rule-only: the kernel audit subsystem loads the rules below and emits
  # events to the kernel log, where journald captures them for the log
  # pipeline (journal → loki).  The userspace auditd daemon is left off on
  # purpose — running the daemon alongside the auditctl rule loader makes
  # the loader's `auditctl -b` (backlog) call fail, since the live daemon
  # owns the audit backlog.  One mechanism, no /var/log/audit on disk.
  security = {
    auditd.enable = false;
    audit.enable = true;
    audit.rules = [
      "-a exit,always -F arch=b64 -S execve"
    ];
  };
}
