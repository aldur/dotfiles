{
  probeFiles."signal-probe.sh" = "${./probe.sh}";
  probeFiles."signal-sandbox.sh" = "${./sandbox.sh}";
  extraProbe = ''
    set -E
    trap 'journalctl -b --no-pager -n 100' ERR
    # This disposable test password is never present in the production image.
    printf 'test-only-keyring-password' | as_user gnome-keyring-daemon --replace --unlock --components=secrets
    in_session signal-desktop
    for _ in $(seq 120); do
      if user="$user" bash -e "$probe/signal-probe.sh"; then break; fi
      sleep 1
    done
    user="$user" bash -e "$probe/signal-probe.sh"
    user="$user" bash -e "$probe/signal-sandbox.sh"
    pid=$(as_user systemctl --user show signal -p MainPID --value)
    printf 'nameserver 100.115.92.1\n' > /run/resolv.conf.next
    mv /run/resolv.conf.next /run/resolv.conf
    nsenter -t "$pid" -m -- grep -Fx 'nameserver 127.0.0.53' /etc/resolv.conf
    echo "PROBE signal encrypted and sandboxed"
    as_user systemctl --user stop signal.service
  '';
  extraChecks = [ "signal encrypted and sandboxed$" ];
}
