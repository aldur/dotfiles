{ lib, ... }:
{
  security = {
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
      execWheelOnly = true;
    };
  };

  # --- Mitigation against CVE-2026-31431/copy.fail ---
  boot.blacklistedKernelModules = [
    "algif_aead"
  ];

  boot.extraModprobeConfig = ''
    install algif_aead /bin/false
  '';
  # --- /Mitigation against CVE-2026-31431/copy.fail ---
}
