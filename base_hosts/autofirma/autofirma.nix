{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./desktop.nix
  ];

  aldur.qemuGuest.sshHostKeyDir = ./.;

  virtualisation.graphics = true;
}
