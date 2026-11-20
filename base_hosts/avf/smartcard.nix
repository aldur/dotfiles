# A virtual smart card reader (vpcd of vsmartcard) for the PIV applet of a
# YubiKey. The Android app Smart Card Reader
# (com.vsmartcard.remotesmartcardreader.app) reads the key over NFC and
# connects to vpcd on 127.0.0.1 through the port forwarding of the Terminal
# app.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # forwarder_guest_launcher in AOSP keeps the guest port as an i16. Thus the
  # Terminal app cannot forward the vpcd default port 35963.
  port = 25963;
  pcsclite = if config.security.polkit.enable then pkgs.pcscliteWithPolkit else pkgs.pcsclite;

  # Only the driver of the package, without debug information. The package
  # installs the driver in var, which the strip hook of Nixpkgs does not
  # strip. The include paths in the debug information keep gcc and the
  # headers in the closure. The package also contains vicc and its Python.
  vpcdDriver = pkgs.runCommandCC "libifdvpcd" { } ''
    install -D -m 755 ${pkgs.vsmartcard-vpcd}/var/lib/pcsc/drivers/serial/libifdvpcd.so \
      $out/lib/libifdvpcd.so
    $STRIP --strip-debug $out/lib/libifdvpcd.so
  '';
in
{
  services.pcscd = {
    enable = true;
    readerConfigs = [
      ''
        FRIENDLYNAME "Virtual PCD"
        DEVICENAME   /dev/null:${toString port}
        LIBPATH      ${vpcdDriver}/lib/libifdvpcd.so
        CHANNELID    ${toString port}
      ''
    ];
  };

  # All SSH connections sign with the PIV key through pcscd. ssh asks for
  # the PIN in the terminal. The PKCS#11 module of Yubico uses only readers
  # with "Yubikey" in the name.
  programs.ssh.extraConfig = ''
    Host *
      PKCS11Provider ${pkgs.opensc}/lib/opensc-pkcs11.so
  '';

  # vpcd listens only while pcscd runs. Start pcscd at boot, without
  # --auto-exit.
  systemd.services.pcscd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${lib.getExe pcsclite} --foreground --config /etc/reader.conf"
    ];
  };
}
