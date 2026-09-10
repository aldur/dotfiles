{
  lib,
  writeArgcApplication,
  tart,
  coreutils,
  openssh,
  nix,
  inputs ? { },
  guestSystem ? inputs.macos-vm.lib.mkGuestSystem inputs,
  defaultVmDir ? "$HOME/.local/share/macos-vm",
  defaultMemory ? 8192,
  defaultCores ? 4,
  defaultDiskSize ? 64,
}:
writeArgcApplication {
  name = "macos-vm";
  runtimeInputs = [
    tart
    coreutils
    openssh
    nix
  ];
  text = ''
    # shellcheck disable=SC2016
    default_dir=${lib.escapeShellArg defaultVmDir}
    default_memory=${toString defaultMemory}
    default_cores=${toString defaultCores}
    default_disk_size=${toString defaultDiskSize}
    guest_system=${guestSystem}
    bootstrap_script=${./bootstrap.sh}
  ''
  + builtins.readFile ./launcher.sh;
  meta = {
    description = "Run an unattended macOS VM provisioned with the repository's nix-darwin configuration";
    platforms = [ "aarch64-darwin" ];
  };
}
