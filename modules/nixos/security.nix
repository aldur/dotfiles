{ lib, ... }:
{
  security = {
    # https://emudhra.we-have-a-problem.com/
    pki.caCertificateBlacklist = [
      "Comodo AAA Services root"
      "emSign ECC Root CA - G3"
    ];

    sudo.enable = false;
    sudo-rs = {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
      execWheelOnly = true;
    };
  };
}
