# The boot check of the Baguette image, with the probes of this guest on
# top of utils/baguette-test.nix of the dotfiles.
{
  lib,
  runCommand,
  xz,
  zstd,
  mkBaguetteTest,
  configuration,
}:
let
  kernel = configuration.config.boot.kernelPackages.kernel;

  # A module of the test kernel, uncompressed. The guest must refuse to
  # load it: crostini.nix sets kernel.modules_disabled.
  module =
    runCommand "dummy.ko"
      {
        nativeBuildInputs = [
          xz
          zstd
        ];
      }
      ''
        src=$(echo ${kernel.modules}/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/dummy.ko*)
        case "$src" in
          *.xz) xz -dc "$src" > $out ;;
          *.zst) zstd -dc "$src" > $out ;;
          *) cp "$src" $out ;;
        esac
      '';
in
mkBaguetteTest {
  inherit configuration;
  name = "crostini-baguette-boot";
  probeFiles.module = module;
  extraProbe = ''
    echo "PROBE sysctl $(systemctl is-active systemd-sysctl.service) modules_disabled=$(sysctl -n kernel.modules_disabled)"
    echo "PROBE lockdown $(cat /sys/kernel/security/lockdown 2>/dev/null || echo absent)"
    echo "PROBE insmod $(insmod $probe/module 2>&1 || true)"
    for target in /home /nix/store /home/$user/.claude; do
      echo "PROBE mount $target $(findmnt -n -o OPTIONS $target)"
    done
  '';
  # EPERM with no lockdown and the sysctl at 1 comes from modules_disabled
  # alone.
  extraChecks = [
    "sysctl active modules_disabled=1"
    "lockdown \\(absent\\|\\[none\\]\\)"
    "insmod .*Operation not permitted"
  ];
}
