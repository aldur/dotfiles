{ pkgs }:
let
  applicationProbe = ''
    (
      # CPU contention exposes the telemetry shutdown race in short sessions.
      load_pids=()
      trap 'kill "''${load_pids[@]}" 2>/dev/null || true' EXIT
      for _ in 1 2; do
        yes > /dev/null &
        load_pids+=($!)
      done
      for attempt in $(seq 50); do
        rm -f /home/$user/browser.png
        in_session --unit="browser-smoke-$attempt" --property=RuntimeMaxSec=180 firefox --headless \
          --screenshot /home/$user/browser.png about:blank \
          > /tmp/firefox.log 2>&1 || {
            status=$?
            echo "Firefox screenshot $attempt exited with status $status" >&2
            cat /tmp/firefox.log
            journalctl -b _UID="$(id -u "$user")" --no-pager -n 100 || true
            journalctl -k -b --no-pager -n 100 || true
            exit "$status"
          }
        test -s /home/$user/browser.png
      done
    )
    grep -Fx 'x-scheme-handler/https=firefox.desktop' /etc/xdg/mimeapps.list
    echo "PROBE browser rendered"
  '';
in
{
  reboots = 1;
  extraProbe = applicationProbe + ''
    user="$user" persist=.config/mozilla bash "$probe/appliance-state.sh" plant
  '';
  extraChecks = [
    "browser rendered$"
    "state plant$"
  ];
  secondProbe = ''
    user="$user" persist=.config/mozilla bash "$probe/appliance-state.sh" verify
  '' + applicationProbe;
  secondChecks = [
    "state verify$"
    "browser rendered$"
  ];
}
