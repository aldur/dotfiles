{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;
  uid = toString config.users.users.${user}.uid;
  wayland = config.services.cage.enable;
  home = config.users.users.${user}.home;
  signal = import ./package.nix { inherit pkgs; };
  keyring = pkgs.gnome-keyring.override { useWrappedDaemon = false; };
  serviceHardening = {
    SystemCallArchitectures = "native";
    RestrictRealtime = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    PrivateTmp = true;
  };
  daemonHardening = serviceHardening // {
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
  };
  launcher = pkgs.writeShellApplication {
    name = "signal-desktop";
    passthru = { inherit signal; };
    meta.description = "Signal";
    runtimeInputs = [
      pkgs.argc
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.glib
      pkgs.systemd
      keyring
      pkgs.yad
    ];
    text = builtins.readFile ./launcher.sh + ''
      mkdir -p "$HOME/.config/Signal" "$HOME/.cache"
      systemctl --user import-environment DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
      systemctl --user start ${lib.optionalString wayland "--wait"} signal.service
    '';
  };
  # Restrict all traffic from the session account, including a compromised
  # Electron main process. Only the local DNS stub is exempt.
  private4 = "0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,198.18.0.0/15,224.0.0.0/4,240.0.0.0/4";
in
{
  imports = [ "${inputs.self}/base_hosts/appliance/guest.nix" ];
  aldur.appliance.application = launcher;
  users.users.${user}.uid = 1000;
  environment.systemPackages = [
    launcher
    keyring
    (pkgs.makeDesktopItem {
      name = "signal";
      desktopName = "Signal";
      exec = "signal-desktop";
      icon = "${signal}/share/icons/hicolor/256x256/apps/signal-desktop.png";
      categories = [
        "Network"
        "InstantMessaging"
      ];
    })
    (pkgs.makeDesktopItem {
      name = "blocked-url";
      desktopName = "External links disabled";
      exec = "${pkgs.coreutils}/bin/false";
      noDisplay = true;
    })
  ];
  services.dbus.packages = [ keyring ];
  xdg.portal.enable = lib.mkForce false;
  xdg.mime.defaultApplications = lib.genAttrs [
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "text/html"
  ] (_: lib.mkForce "blocked-url.desktop");
  # Maitred replaces /run/resolv.conf when ChromeOS changes DNS servers.
  # Keep that upstream file outside the application's mount namespace.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      listen-address = "127.0.0.53";
      bind-interfaces = true;
      resolv-file = "/etc/resolv.conf";
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/dnsmasq 0750 dnsmasq dnsmasq -" ];
  systemd.services.dnsmasq = {
    # The upstream pre-start changes ownership, which needs CAP_CHOWN.
    preStart = lib.mkForce "dnsmasq --test -C ${config.services.dnsmasq.configFile}";
    serviceConfig = daemonHardening // {
      PrivateDevices = true;
      # D-Bus mode requires NET_RAW for dynamic upstream interface binding.
      Type = lib.mkForce "simple";
      BusName = lib.mkForce "";
      ExecStart = lib.mkForce "${pkgs.dnsmasq}/bin/dnsmasq -k --user=dnsmasq -C ${config.services.dnsmasq.configFile}";
      ProtectSystem = lib.mkForce "strict";
      ReadWritePaths = [ "/var/lib/dnsmasq" ];
      CapabilityBoundingSet = [
        "CAP_NET_BIND_SERVICE"
        "CAP_SETUID"
        "CAP_SETGID"
      ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
    };
  };
  systemd.services.firewall.unitConfig.FailureAction = "poweroff-force";

  networking.firewall = {
    allowedTCPPorts = lib.mkForce [ ];
    allowedUDPPorts = lib.mkForce [ ];
    extraCommands = ''
      for cmd in iptables ip6tables; do
        $cmd -N signal-egress 2>/dev/null || true
        $cmd -F signal-egress
      done
      iptables -A signal-egress -d 127.0.0.53 -p udp --dport 53 -j RETURN
      iptables -A signal-egress -d 127.0.0.53 -p tcp --dport 53 -j RETURN
      iptables -A signal-egress -d ${private4} -j REJECT
      ip6tables -A signal-egress ! -d 2000::/3 -j REJECT
      for cmd in iptables ip6tables; do
        $cmd -A OUTPUT -m owner --uid-owner ${uid} -j signal-egress
      done
    '';
    extraStopCommands = ''
      for cmd in iptables ip6tables; do
        $cmd -D OUTPUT -m owner --uid-owner ${uid} -j signal-egress 2>/dev/null || true
        $cmd -F signal-egress 2>/dev/null || true
        $cmd -X signal-egress 2>/dev/null || true
      done
    '';
  };

  systemd.user.services.signal-preflight = {
    description = "Check Signal prerequisites";
    serviceConfig = serviceHardening // {
      Type = "oneshot";
      ExecStart = [
        "${launcher}/bin/signal-desktop --check"
      ]
      ++ map (unit: "${pkgs.systemd}/bin/systemctl --system is-active --quiet ${unit}.service") [
        "firewall"
        "dnsmasq"
      ];
      CapabilityBoundingSet = "";
      PrivateUsers = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };

  systemd.user.services.signal-bus = {
    description = "Signal Secret Service proxy";
    serviceConfig = daemonHardening // {
      SystemCallFilter = [ "@system-service" ];
      PrivatePIDs = true;
      # PID 1 ignores the proxy's default SIGTERM action.
      KillSignal = "SIGKILL";
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/signal-bus";
      ExecStart = lib.concatStringsSep " " (
        [
          "${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy unix:path=%t/bus %t/signal-bus --filter --see=org.freedesktop.secrets"
        ]
        ++
          lib.concatMap
            (
              interface:
              map (rule: "--${rule}=org.freedesktop.secrets=${interface}.*") [
                "call"
                "broadcast"
              ]
            )
            # Proxy rules require each interface name; .* selects its methods.
            (
              [ "org.freedesktop.DBus.Properties" ]
              ++ map (interface: "org.freedesktop.Secret.${interface}") [
                "Service"
                "Collection"
                "Item"
                "Session"
                "Prompt"
              ]
            )
      );
      ExecStartPost = "${pkgs.writeShellScript "wait-signal-bus" ''
        until ${pkgs.systemd}/bin/busctl --address="$1" --timeout=1 list >/dev/null 2>&1; do
          sleep 0.1
        done
      ''} unix:path=%t/signal-bus";
      ExecStopPost = "${pkgs.coreutils}/bin/rm -f %t/signal-bus";
      TimeoutStartSec = 10;
      UMask = "0077";
      CapabilityBoundingSet = "";
      PrivateUsers = true;
      ProtectSystem = "strict";
      ProtectHome = "tmpfs";
      BindPaths = [ "%t" ];
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };

  systemd.user.services.signal = {
    description = "Signal Desktop";
    requires = [
      "signal-preflight.service"
    ];
    bindsTo = [ "signal-bus.service" ];
    after = [
      "signal-preflight.service"
      "signal-bus.service"
    ];
    environment = {
      BROWSER = "${pkgs.coreutils}/bin/false";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=%t/bus";
    }
    // lib.optionalAttrs wayland { GDK_BACKEND = "wayland"; };
    serviceConfig = serviceHardening // {
      ExecStart = "${signal}/bin/signal-desktop --password-store=gnome-libsecret --ozone-platform=${
        if wayland then "wayland" else "x11"
      } --disable-gpu";
      UMask = "0077";
      LimitCORE = "0";
      UnsetEnvironment = [
        "NODE_OPTIONS"
        "NODE_PATH"
        "ELECTRON_RUN_AS_NODE"
        "ELECTRON_ENABLE_LOGGING"
      ];
      CapabilityBoundingSet = "";
      PrivateUsers = true;
      # Resolver updates replace files in /run. A private parent mount keeps
      # those replacements from hiding the application's resolver bind mount.
      TemporaryFileSystem = [ "/run:ro" ];
      BindReadOnlyPaths = [
        "/run/current-system"
        "-/run/opengl-driver"
        "%t/signal-bus:%t/bus"
        "${pkgs.writeText "signal-resolv.conf" "nameserver 127.0.0.53\n"}:/etc/resolv.conf"
      ]
      ++ (
        if wayland then
          [ "%t/wayland-0" ]
        else
          [
            "/tmp/.X11-unix"
            "-${home}/.Xauthority"
          ]
      );
      ProtectSystem = "strict";
      ProtectHome = "tmpfs";
      BindPaths = [
        "${home}/.config/Signal"
        "${home}/.cache"
      ];
      InaccessiblePaths = [
        "-/mnt"
        "-/media"
        "-/run/media"
        "-/dev/dri"
      ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      # Namespaces remain available for Chromium's own renderer sandbox.
      StandardOutput = "null";
      StandardError = "journal";
      TimeoutStopSec = 30;
    };
  };
}
