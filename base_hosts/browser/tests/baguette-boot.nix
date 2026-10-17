{
  extraProbe = ''
    # Run the shipped browser as the ordinary session user. This catches
    # sandbox/graphics regressions from hardening without a network login.
    in_session --property=RuntimeMaxSec=180 firefox --headless \
      --screenshot /home/$user/browser.png about:blank \
      > /tmp/firefox.log 2>&1 || { cat /tmp/firefox.log; exit 1; }
    test -s /home/$user/browser.png
    in_session xdg-mime query default x-scheme-handler/https | grep -Fx firefox.desktop
    echo "PROBE browser rendered"
  '';
  extraChecks = [
    "browser rendered$"
  ];
}
