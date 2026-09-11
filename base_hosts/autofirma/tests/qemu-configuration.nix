# Guard the production settings that the signing scenario does not need to
# change. The driver, local HTTPS fixture and input devices remain explicit
# test instrumentation; they must not replace storage or application setup.
{
  pkgs,
  lib,
  production,
  tested,
}:
let
  select = c: {
    inherit (c) mainUser;
    inherit (c.virtualisation) useNixStoreImage writableStore sharedDirectories;
    inherit (c.environment) loginShellInit sessionVariables;
    inherit (c.hardware.graphics) enable;
    inherit (c.aldur.autofirma) filesDir;
    user = {
      inherit (c.users.users.${c.mainUser})
        uid
        home
        homeMode
        extraGroups
        ;
    };
    kernel = c.boot.kernelPackages.kernel.drvPath;
    initrd = c.boot.initrd.enable;
    firefox = c.programs.firefox.finalPackage.drvPath;
    autofirma = c.programs.autofirma.finalPackage.drvPath;
    logrotate = c.services.logrotate.enable;
    manager = c.systemd.settings.Manager;
    userManager = c.systemd.user.extraConfig;
  };
  expected = select production;
  actual = select tested;
  differences = lib.filter (key: expected.${key} != actual.${key}) (lib.attrNames expected);
in
assert lib.assertMsg (
  differences == [ ]
) "AutoFirma signing test differs from production: ${lib.concatStringsSep ", " differences}";
pkgs.runCommand "autofirma-qemu-configuration" { } ''
  touch "$out"
''
