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

  boot.blacklistedKernelModules = [
    # --- Mitigation against CVE-2026-31431/copy.fail ---
    "algif_aead"
    # --- /Mitigation against CVE-2026-31431/copy.fail ---

    # --- Mitigation against dirtyfrag ---
    "esp4"
    "esp6"
    "rxrpc"
    # --- /Mitigation against dirtyfrag ---
  ];
}
