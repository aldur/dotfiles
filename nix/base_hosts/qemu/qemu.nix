{ config, hostPkgs, inputs, ... }: {
  imports = [ "${inputs.self}/modules/current_system_flake.nix" ];

  virtualisation.diskSize = 64 * 1024;

  # By default `nix` builds under /tmp, which is constrained by RAM size:
  # https://discourse.nixos.org/t/
  # no-space-left-on-device-error-when-rebuilding-but-plenty-of-storage-available/43862/9
  virtualisation.memorySize = 16 * 1024;
  virtualisation.cores = 8;

  # Instead, write to the machine's filesystem.
  virtualisation.writableStoreUseTmpfs = false;

  # This allows building from macOS
  virtualisation.qemu.package = hostPkgs.qemu;
  virtualisation.host.pkgs = hostPkgs;

  programs.aldur.lazyvim.enable = true;
  programs.aldur.lazyvim.packageNames = [ "lazyvim" ];

  programs.better-nix-search.enable = true;

  networking.hostName = "qemu-nixos";

  services.getty.autologinUser = config.users.users.aldur.name;
  security.sudo-rs.wheelNeedsPassword = false;

  environment = { sessionVariables = { TERM = "screen-256color"; }; };

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      mode = "0600";
      source = ./ssh_host_ed25519_key;
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      mode = "0644";
      source = ./ssh_host_ed25519_key.pub;
    };
  };

  services.getty.helpLine = ''
    Type 'Ctrl-a c' from `bash` to switch to the QEMU console.
  '';

  # Disable virtual console
  systemd.services."autovt@".enable = false;
  systemd.services."getty@".enable = false;
}
