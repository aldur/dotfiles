# The display and the sound of the guest on virtio-gpu, virtio input devices
# and a virtio-snd card, as the Terminal app attaches them. The test cannot
# cover gfxstream and the display view of the app.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "avf-display";

  nodes.machine =
    { lib, pkgs, ... }:
    {
      imports = [
        ../agent.nix
        ../terminal-display.nix
      ];
      options.mainUser = lib.mkOption { default = "aldur"; };
      config = {
        # pactl, pacat and parec use pipewire-pulse.
        environment.systemPackages = [
          pkgs.pulseaudio
          pkgs.wl-clipboard
          pkgs.xprop
        ];
        users.users.aldur = {
          isNormalUser = true;
          uid = 1000;
        };
        virtualisation.memorySize = 2048;
        virtualisation.qemu.options = [
          "-vga none"
          "-device virtio-gpu-pci"
          "-device virtio-keyboard-pci"
          "-device virtio-tablet-pci"
          "-audiodev none,id=snd0"
          "-device virtio-sound-pci,audiodev=snd0"
        ];
      };
    };

  testScript = ''
    machine.wait_for_unit("weston.service")
    machine.succeed("loginctl list-sessions --no-legend | grep -q seat0")

    with subtest("weston has only the dependencies of the guest"):
        session = machine.succeed("systemctl show -P ExecStart weston | grep -o '/nix/store/[^ ;]*'").split()[0]
        closure = machine.succeed(f"nix-store -qR {session}")
        for unwanted in ["freerdp", "neatvnc", "sdl3", "gtk4", "gtk+3", "gstreamer", "pipewire"]:
            assert unwanted not in closure, closure

    with subtest("PipeWire has only the dependencies of the guest"):
        closure = machine.succeed(
            "nix-store -qR $(readlink -f /run/current-system/sw/bin/pipewire /run/current-system/sw/bin/wireplumber)"
        )
        for unwanted in ["ffmpeg", "bluez", "libcamera", "gstreamer", "roc-toolkit", "ffado", "libjack2"]:
            assert unwanted not in closure, unwanted

    # The calls of the agent of the Terminal app, as its user and with its PATH.
    with subtest("the agent reads and writes the clipboard on wayland-0"):
        machine.wait_for_file("/run/user/1000/wayland-0")
        path = machine.succeed("systemctl show -P Environment linux-vm-manager | grep -o 'PATH=[^ ]*'").strip()
        sudo = f"runuser -u aldur -- env {path} sudo -u droid XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
        machine.succeed(f"echo -n hello | {sudo} wl-copy")
        assert machine.succeed(f"{sudo} wl-paste --no-newline") == "hello"
        # wl-copy stays to serve the clipboard. It runs as the main user.
        machine.succeed("pgrep -u aldur -f bin/wl-copy")
        machine.fail("pgrep -u root -f bin/wl-copy")

    with subtest("Xwayland serves :0"):
        machine.wait_until_succeeds("su - aldur -c 'DISPLAY=:0 xprop -root'")

    with subtest("PipeWire plays and records on the virtio-snd card"):
        pactl = "su - aldur -c 'XDG_RUNTIME_DIR=/run/user/1000 pactl list short {}'"
        machine.wait_until_succeeds(pactl.format("sinks") + " | grep -q alsa_output")
        machine.succeed(pactl.format("sources") + " | grep -q alsa_input")
        machine.succeed(
            "su - aldur -c 'XDG_RUNTIME_DIR=/run/user/1000"
            " timeout 2 pacat --raw /dev/zero; test $? = 124'"
        )
        machine.succeed(
            "su - aldur -c 'XDG_RUNTIME_DIR=/run/user/1000"
            " timeout 2 parec --raw > /dev/null; test $? = 124'"
        )

    machine.succeed("systemctl is-active weston")
  '';
}
