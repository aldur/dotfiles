{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./guest.nix
  ];

  aldur.qemuGuest.sshHostKeyDir = ./.;

  virtualisation.graphics = true;
}
