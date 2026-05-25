_: {
  # NOTE: This is not included in the default configuration,
  # but is exposed as a flake output.
  security = {
    auditd.enable = true;
    audit.enable = true;
    audit.rules = [
      "-a exit,always -F arch=b64 -S execve"
    ];
  };
}
