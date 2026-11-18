# The display and the sound of the Android Terminal app, as in the Debian
# guest. The app attaches a virtio-gpu display, virtio input devices and a
# virtio-snd card. Its display view shows the weston session on tty1.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The app adds gfxstream_enabled to the kernel command line when the GPU
  # renderer is selected in its settings. OpenGL then uses zink on the
  # gfxstream Vulkan driver. The other renderer is lavapipe, the Mesa default.
  graphicsEnv = pkgs.writeText "terminal-graphics-env" ''
    if ${lib.getExe pkgs.gnugrep} -qw gfxstream_enabled /proc/cmdline; then
      export MESA_LOADER_DRIVER_OVERRIDE=zink
      export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/gfxstream_vk_icd.${pkgs.stdenv.hostPlatform.uname.processor}.json
      export MESA_VK_WSI_DEBUG=sw,linear
      export XWAYLAND_NO_GLAMOR=1
      export LIBGL_KOPPER_DRI2=1
    fi
  '';

  westonIni = lib.generators.toINI { } {
    core.idle-time = 0;
    shell = {
      panel-position = "none";
      locking = false;
    };
    # The touchpad of crosvm sets INPUT_PROP_BUTTONPAD, which disables tap to
    # click by default.
    libinput = {
      enable-tap = true;
      accel-speed = 0.5;
    };
  };

  # A copy of the cached package DRV without the files in REMOVE. The copy
  # does not compile anything. It has the same name, so its store path has
  # the same length, as in replaceDirectDependencies of Nixpkgs. REPLACEMENTS
  # changes more store paths in the copy.
  repack =
    {
      drv,
      remove ? [ ],
      replacements ? [ ],
    }:
    let
      rewrites = [
        {
          oldDependency = drv;
          newDependency = placeholder "out";
        }
      ]
      ++ replacements;
    in
    pkgs.runCommandLocal drv.name
      {
        nativeBuildInputs = [ config.nix.package.out ];
        disallowedReferences = map (r: r.oldDependency) rewrites;
        inherit (drv) meta;
        # meta.outputsToInstall of PipeWire includes the man pages.
        passthru = lib.optionalAttrs (drv ? man) { inherit (drv) man; };
      }
      ''
        nix-store --dump ${drv} \
          | sed ${
            lib.concatMapStringsSep " " (r: "-e 's|${r.oldDependency}|${r.newDependency}|g'") rewrites
          } \
          | nix-store --restore $out
        ${lib.concatMapStrings (f: "rm -r $out/${f}\n") remove}
        # Remove the links to the removed files.
        find $out -xtype l -delete
      '';

  # Xwayland uses libdecor only for a rootful window. The cairo plugin stays.
  # The GTK plugin pulls in GTK 3.
  libdecor = repack {
    drv = pkgs.libdecor;
    remove = [ "lib/libdecor/plugins-1/libdecor-gtk.so" ];
  };
  xwayland = repack {
    drv = pkgs.xwayland;
    replacements = [
      {
        oldDependency = pkgs.libdecor;
        newDependency = libdecor;
      }
    ];
  };
  # PipeWire without the plugins for devices and protocols that the guest
  # does not have: Bluetooth, cameras, FireWire, JACK, GStreamer, network
  # audio, video and the X11 bell. pw-cat (pw-play, pw-record) and the
  # FFmpeg plugins link FFmpeg.
  pipewire = repack {
    drv = pkgs.pipewire;
    remove = [
      "bin/pw-cat"
      "lib/gstreamer-1.0"
      "lib/pipewire-0.3/libpipewire-module-ffado-driver.so"
      "lib/pipewire-0.3/libpipewire-module-jack-tunnel.so"
      "lib/pipewire-0.3/libpipewire-module-roc-sink.so"
      "lib/pipewire-0.3/libpipewire-module-roc-source.so"
      "lib/pipewire-0.3/libpipewire-module-x11-bell.so"
      "lib/spa-0.2/aec/libspa-aec-webrtc.so"
      "lib/spa-0.2/bluez5"
      "lib/spa-0.2/ffmpeg"
      "lib/spa-0.2/filter-graph/libspa-filter-graph-plugin-ffmpeg.so"
      "lib/spa-0.2/filter-graph/libspa-filter-graph-plugin-lv2.so"
      "lib/spa-0.2/filter-graph/libspa-filter-graph-plugin-sofa.so"
      "lib/spa-0.2/jack"
      "lib/spa-0.2/libcamera"
      "lib/spa-0.2/videoconvert"
    ];
  };
  wireplumber = repack {
    drv = pkgs.wireplumber;
    replacements = [
      {
        oldDependency = pkgs.pipewire;
        newDependency = pipewire;
      }
    ];
  };

  # Weston without remote desktop and screen capture. These plugins pull in
  # FreeRDP, SDL, GTK 4, GStreamer and PipeWire.
  weston = repack {
    drv = pkgs.weston;
    remove = map (m: "lib/libweston-15/${m}.so") [
      "pipewire-backend"
      "pipewire-plugin"
      "rdp-backend"
      "remoting-plugin"
      "vnc-backend"
    ];
    replacements = [
      {
        oldDependency = pkgs.xwayland;
        newDependency = xwayland;
      }
    ];
  };

  # The agent connects to wayland-0. Without --socket, weston uses wayland-1.
  westonSession = pkgs.writeShellScript "weston-session" ''
    . ${graphicsEnv}
    exec ${lib.getExe weston} --backend=drm --socket=wayland-0 --xwayland \
      --continue-without-input --modules=systemd-notify.so \
      --config=${pkgs.writeText "weston.ini" westonIni}
  '';
in
{
  hardware.graphics.enable = true;

  # Based on the cage-tty1 service of Nixpkgs: the PAM session gives weston
  # the seat of the display.
  systemd.services.weston = {
    description = "Weston on the display of the Terminal app";
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
      "getty@tty1.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    conflicts = [ "getty@tty1.service" ];
    wantedBy = [ "graphical.target" ];
    restartIfChanged = false;
    environment.XDG_SESSION_TYPE = "wayland";
    serviceConfig = {
      Type = "notify";
      ExecStart = westonSession;
      User = config.mainUser;
      PAMName = "weston";
      UtmpIdentifier = "%n";
      UtmpMode = "user";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      Restart = "always";
      RestartSec = 3;
    };
  };
  security.pam.services.weston.startSession = true;
  systemd.defaultUnit = "graphical.target";

  # As in the Debian guest, programs started from the terminal show on the
  # display.
  environment.extraInit = ''
    export DISPLAY=:0 WAYLAND_DISPLAY=wayland-0
    . ${graphicsEnv}
  '';

  services.pipewire = {
    enable = true;
    package = pipewire;
    wireplumber = {
      package = wireplumber;
      # The copy of PipeWire has no plugins for these devices.
      extraConfig."10-terminal-monitors"."wireplumber.profiles".main = {
        "monitor.bluez" = "disabled";
        "monitor.bluez-midi" = "disabled";
        "monitor.libcamera" = "disabled";
      };
    };
    alsa.enable = true;
    pulse.enable = true;
  };
  users.users.${config.mainUser}.extraGroups = [ "audio" ];
}
