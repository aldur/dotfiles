{
  pkgs,
  mkLauncher,
  darwinMkLauncher,
}:
let
  # Use the production launcher factory without building any guest image.
  fixture = {
    name = "qemu-vm-preflight";
    bootArgs = "-S";
    bootFiles = [ ];
    storeImage = "/no/such/store.img";
    excludeShellChecks = [ "SC2034" ];
  };
  launcher = mkLauncher fixture;
  # Run macOS argument handling on Linux too. All cases stop before any
  # host-specific commands; discard guest/host store references deliberately.
  darwinPreflight = pkgs.writeShellApplication {
    name = "qemu-vm-darwin-preflight";
    runtimeInputs = [
      pkgs.argc
      pkgs.coreutils
    ];
    excludeShellChecks = fixture.excludeShellChecks;
    text = builtins.unsafeDiscardStringContext (darwinMkLauncher fixture).launcherText;
  };
in
pkgs.runCommand "qemu-vm-preflight"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${./preflight.py} \
      ${pkgs.lib.getExe launcher} \
      ${pkgs.lib.getExe darwinPreflight}
    touch "$out"
  ''
