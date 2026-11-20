# The SSH agent of the guest. The Android app holds the YubiKey and is the
# agent. The bridge in the guest is a pipe: it serves the agent socket and
# sends each request to the app. The app connects to the bridge on
# 127.0.0.1 through the port forwarding of the Terminal app.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;
  socket = "/run/avf-ssh-agent/agent.sock";
in
{
  # `avf-ssh-agent pair` and `avf-ssh-agent status`.
  environment.systemPackages = [ pkgs.avf-ssh-agent ];

  systemd.services.avf-ssh-agent = {
    description = "SSH agent bridge to the Android app";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.avf-ssh-agent} serve";
      User = user;
      Group = config.users.users.${user}.group;
      RuntimeDirectory = "avf-ssh-agent";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "avf-ssh-agent";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = 1;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };

  # ssh-add reads the variable. ssh reads IdentityAgent, also for root.
  environment.variables.SSH_AUTH_SOCK = socket;
  programs.ssh.extraConfig = ''
    Host *
      IdentityAgent ${socket}
  '';
}
