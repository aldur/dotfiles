# The guest agent of the Terminal app: linux_vm_manager in
# guest/linux_vm_manager of AOSP. It handles shutdown, the storage balloon,
# the clipboard and port forwarding. As garcon in ChromeOS, it runs as the
# main user and cannot get more privileges. For each of the three tasks that
# need root, a system unit does only that task.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;
  inherit (config.users.users.${user}) group;
  tcpstatesSocket = "/run/terminal-tcpstates.sock";
  poweroffRequest = "/run/linux-vm-manager/poweroff";

  # The agent reads and writes the clipboard of the display with these two
  # calls (updateClipboard and readClipboard in debian_service.rs). droid is
  # the user of the Debian guest. The agent is already the main user.
  clipboardSudo = pkgs.writeShellApplication {
    name = "sudo";
    text = ''
      prefix="-u droid XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
      case "$(printf '%q ' "$@")" in
      "$prefix wl-copy ") command=(${lib.getExe' pkgs.wl-clipboard "wl-copy"}) ;;
      "$prefix wl-paste --no-newline ") command=(${lib.getExe' pkgs.wl-clipboard "wl-paste"} --no-newline) ;;
      *)
        echo "sudo: not a clipboard call of the agent: $*" >&2
        exit 1
        ;;
      esac
      export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
      exec "''${command[@]}"
    '';
  };

  # shutdown_runner runs poweroff. Only root can power off, so this asks
  # terminal-poweroff.path.
  poweroff = pkgs.writeShellApplication {
    name = "poweroff";
    runtimeInputs = [ pkgs.coreutils ];
    text = "touch ${poweroffRequest}";
  };

  # forwarder_guest_launcher reads the output of this program to find the TCP
  # ports to forward to Android. tcpstates needs capabilities, so
  # terminal-tcpstates.socket runs it.
  tcpstatesClient = pkgs.writeShellApplication {
    name = "tcpstates-libbpf";
    runtimeInputs = [ pkgs.socat ];
    text = "exec socat -u UNIX-CONNECT:${tcpstatesSocket} STDOUT";
  };
  tcpstates = pkgs.callPackage ./tcpstates.nix { };

  # For the ports that listen before it starts, the agent finds the process
  # through the sockets in /proc/PID/fd. The agent cannot see the processes of
  # other users, so it ignores their ports. Thus after the header of
  # tcpstates, this writes a LISTEN line for each of these ports, as the agent
  # does it (IPv4, loopback or all addresses).
  tcpstatesWithListeners = pkgs.writeShellApplication {
    name = "tcpstates-with-listeners";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.iproute2
    ];
    text = ''
      # Without -oL, the output goes to the socket in blocks.
      stdbuf -oL ${lib.getExe tcpstates} | {
        IFS= read -r header
        echo "$header"
        # The columns of tcpstates: SKADDR PID COMM LADDR LPORT RADDR RPORT
        # OLDSTATE -> NEWSTATE MS.
        ss -4 -ltnpH | gawk '{
          address = $4
          port = address
          sub(/:[0-9]+$/, "", address)
          sub(/^.*:/, "", port)
          if (address !~ /^(127\.|0\.0\.0\.0$|\*$)/) next
          if (!match($0, /users:\(\("([^"]*)",pid=([0-9]+)/, owner)) next
          comm = owner[1]
          gsub(/[[:space:]]/, "_", comm)
          print 0, owner[2], comm, address, port, "0.0.0.0", 0, "CLOSE", "->", "LISTEN", 0
        }'
        exec cat
      } | gawk '
        # forwarder_host of the Terminal app closes all its port
        # listeners when two reports of the agent come before it reads the
        # first (EFD_SEMAPHORE in android/forwarder_host/src/forwarder_host.rs).
        # The agent sends a report for each LISTEN or CLOSE line without a
        # remote port. Thus these lines come 1 second apart.
        NR == 1 { for (i = 1; i <= NF; i++) column[$i] = i }
        NR > 1 && $(column["RPORT"]) == 0 && $(column["NEWSTATE"]) ~ /^(LISTEN|CLOSE)$/ {
          system("sleep 1")
        }
        { print; fflush() }
      '
    '';
  };
in
{
  # The agent uses /run/user/1000.
  users.users.${user}.uid = 1000;

  # cidata.iso ships the agent as a musl build in root_files/usr, and
  # cloud-init of the Debian guest copies that tree into /usr. Do the same at
  # each boot, because the app replaces cidata.iso when it updates.
  systemd.services.linux-vm-manager-install = {
    description = "Copy the Android Terminal guest agent from cidata.iso";
    unitConfig.ConditionPathExists = "/dev/vdb";
    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "linux-vm-manager-install";
    };
    script = ''
      mount -t iso9660 -o ro /dev/vdb "$RUNTIME_DIRECTORY"
      cp -R --remove-destination "$RUNTIME_DIRECTORY/root_files/usr/." /usr/
      umount "$RUNTIME_DIRECTORY"
      # The storage balloon of the agent.
      chown ${user} /sys/fs/ext4/vda1/reserved_clusters
    '';
  };

  systemd.services.linux-vm-manager = {
    description = "Android Terminal guest agent";
    wantedBy = [ "multi-user.target" ];
    requires = [ "linux-vm-manager-install.service" ];
    after = [
      "linux-vm-manager-install.service"
      "network.target"
    ];
    unitConfig.ConditionPathExists = "/usr/bin/linux_vm_manager";
    path = [
      clipboardSudo
      poweroff
      pkgs.coreutils
      pkgs.socat
      "/usr"
    ];
    serviceConfig = {
      ExecStart = "/usr/bin/linux_vm_manager";
      User = user;
      Group = group;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      RuntimeDirectory = "linux-vm-manager";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  systemd.paths.terminal-poweroff = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExists = poweroffRequest;
  };
  systemd.services.terminal-poweroff = {
    description = "Power off at the request of the guest agent";
    serviceConfig.ExecStart = "${config.systemd.package}/bin/systemctl poweroff";
  };

  systemd.tmpfiles.settings.linux-vm-manager."/usr/sbin/tcpstates-libbpf"."L+".argument =
    lib.getExe tcpstatesClient;
  systemd.sockets.terminal-tcpstates = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = tcpstatesSocket;
      Accept = true;
      SocketUser = user;
      SocketMode = "0600";
      MaxConnections = 4;
    };
  };
  systemd.services."terminal-tcpstates@" = {
    description = "TCP state changes for the guest agent";
    serviceConfig = {
      ExecStart = lib.getExe tcpstatesWithListeners;
      StandardInput = "socket";
      StandardOutput = "socket";
      StandardError = "journal";
      DynamicUser = true;
      # BPF tracing. libbpf reads the ID of the tracepoint in tracefs, which
      # only root can read. ss reads the sockets in /proc/PID/fd of all
      # processes.
      AmbientCapabilities = [
        "CAP_BPF"
        "CAP_PERFMON"
        "CAP_DAC_READ_SEARCH"
        "CAP_SYS_PTRACE"
      ];
      CapabilityBoundingSet = [
        "CAP_BPF"
        "CAP_PERFMON"
        "CAP_DAC_READ_SEARCH"
        "CAP_SYS_PTRACE"
      ];
      # CAP_SYS_PTRACE also gives access to the memory of other processes.
      SystemCallFilter = [
        "~ptrace"
        "~process_vm_readv"
        "~process_vm_writev"
        "~pidfd_getfd"
      ];
      # Thus the service sees only the store and the read-only /proc and /sys.
      TemporaryFileSystem = "/:ro";
      BindReadOnlyPaths = [ builtins.storeDir ];
      MountAPIVFS = true;
      ProtectKernelTunables = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      # ss reads the sockets of the guest, so the service has no network
      # namespace of its own. It sends no IP traffic.
      IPAddressDeny = "any";
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };
}
