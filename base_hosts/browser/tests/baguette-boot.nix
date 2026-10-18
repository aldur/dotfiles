let
  applicationProbe = ''
    in_session --property=RuntimeMaxSec=180 firefox --headless \
      --screenshot /home/$user/browser.png about:blank \
      > /tmp/firefox.log 2>&1 || { cat /tmp/firefox.log; exit 1; }
    test -s /home/$user/browser.png
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
