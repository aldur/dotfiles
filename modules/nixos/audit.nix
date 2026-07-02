_: {
  # NOTE: This is not included in the default configuration, but is exposed as
  # a flake output.
  #
  # Rule-only: the kernel audit subsystem loads the rules below and emits
  # events to the kernel log, where journald captures them for the log pipeline
  # (journal → loki). The userspace auditd daemon is left off on purpose:
  # auditd writing /var/log/audit would only duplicate them on disk where
  # nothing consumes them.
  #
  # Scope execve to processes whose login uid is set (auid != unset): commands
  # run from a login session — an interactive root rebuild, a logged-in user,
  # or an attacker on a hijacked session.  System and daemon processes (every
  # systemd unit, the nix-daemon's builders) carry auid=unset; they are not a
  # forensic signal and auditing them is pure volume.  With no daemon draining
  # the netlink hold queue, that volume overruns the backlog (kauditd hold
  # queue overflow → audit_lost) and the kernel printk-floods the journal.
  # The login-session filter keeps the high-signal subset at a manageable rate.
  # Audit both exec syscalls (execve AND execveat) on both ABIs (b64 AND
  # b32). A single `-S execve -F arch=b64` rule is trivially evaded: an
  # attacker execs via execveat(2), or runs a 32-bit binary (arch=b32) under
  # IA32 emulation, and leaves no session_commands event. The b32 rule loads
  # even where 32-bit execution is impossible — it simply never matches — so
  # it costs nothing there while covering hosts that do allow it. (To drop
  # the b32 attack surface entirely rather than just log it, disable IA32
  # emulation with the `ia32_emulation=0` kernel param.)
  security = {
    auditd.enable = false;
    audit.enable = true;
    audit.rules = [
      "-a always,exit -F arch=b64 -S execve,execveat -F auid!=unset -k session_commands"
      "-a always,exit -F arch=b32 -S execve,execveat -F auid!=unset -k session_commands"
    ];
  };
}
