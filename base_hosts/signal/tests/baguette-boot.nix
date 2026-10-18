let
  applicationProbe = ''
    # This disposable test password is never present in the production image.
    printf 'test-only-keyring-password' | as_user gnome-keyring-daemon --replace --unlock --components=secrets
    in_session signal-desktop
    for _ in $(seq 120); do
      if user="$user" bash -e "$probe/signal-probe.sh"; then break; fi
      sleep 1
    done
    user="$user" bash -e "$probe/signal-probe.sh"
  '';
in
{
  reboots = 1;
  probeFiles."signal-probe.sh" = "${./probe.sh}";
  probeFiles."signal-sandbox.sh" = "${./sandbox.sh}";
  probeFiles."signal-keyring-probe.sh" = "${./keyring.sh}";
  extraProbe = ''
    set -E
    trap 'journalctl -b --no-pager -n 100' ERR
  '' + applicationProbe + ''
    user="$user" bash -e "$probe/signal-sandbox.sh"
    as_user bash -euo pipefail "$probe/signal-keyring-probe.sh"
    pid=$(as_user systemctl --user show signal -p MainPID --value)
    printf 'nameserver 100.115.92.1\n' > /run/resolv.conf.next
    mv /run/resolv.conf.next /run/resolv.conf
    nsenter -t "$pid" -m -- grep -Fx 'nameserver 127.0.0.53' /etc/resolv.conf
    echo "PROBE signal encrypted and sandboxed"
    as_user systemctl --user stop signal.service
    sed -n 's/.*"encryptedKey": *"\([^"]*\)".*/\1/p' \
      /home/$user/.config/Signal/config.json > /state/appliance-encrypted-key
    test -s /state/appliance-encrypted-key
    user="$user" persist='.config/Signal .local/share/keyrings' bash "$probe/appliance-state.sh" plant
  '';
  extraChecks = [
    "signal encrypted and sandboxed$"
    "state plant$"
  ];
  secondProbe = ''
    user="$user" persist='.config/Signal .local/share/keyrings' bash "$probe/appliance-state.sh" verify
  '' + applicationProbe + ''
    encrypted_key=$(sed -n 's/.*"encryptedKey": *"\([^"]*\)".*/\1/p' /home/$user/.config/Signal/config.json)
    test "$encrypted_key" = "$(cat /state/appliance-encrypted-key)"
    echo 'PROBE signal persisted encrypted key'
    as_user systemctl --user stop signal.service
  '';
  secondChecks = [
    "state verify$"
    "signal persisted encrypted key$"
  ];
}
