{
  pkgs,
  lib,
  testCert,
  configuration,
  crostini,
}:
crostini.lib.mkBaguetteSmokeTest {
  inherit configuration;
  name = "autofirma-baguette-smoke";
  probeFiles = {
    "ciudadano.p12" = "${testCert}/ciudadano.p12";
    "password" = "${testCert}/password";
    "signer.pem" = "${testCert}/cert.pem";
  };
  extraProbe = ''
    echo "PROBE home-fs $(findmnt -n -o FSTYPE /home)"
    echo "PROBE pfx $(stat -c %a /etc/Autofirma/autofirma.pfx)"
    echo "PROBE ca $(stat -c %s /etc/Autofirma/Autofirma_ROOT.cer)"
    test -f /run/current-system/sw/share/applications/autofirma-vm-firefox.desktop

    # Files stand in for the host share. Use its production path and the
    # real wrapper; never create the profile/NSS database in the probe.
    files=${lib.escapeShellArg configuration.config.aldur.autofirma.filesDir}
    install -d "$files"
    install -m 0444 "$probe/ciudadano.p12" "$files/cert.p12"
    install -m 0444 "$probe/password" "$files/cert.password"
    in_session --property=RuntimeMaxSec=180 autofirma-vm-firefox --headless \
      --screenshot "/home/$user/start.png" file:///etc/autofirma-vm/index.html \
      > /tmp/firefox.log 2>&1 || { cat /tmp/firefox.log; exit 1; }
    test -s "/home/$user/start.png"
    echo "PROBE firefox rendered"

    # Inspect what the wrapper created without repairing it or injecting
    # MOZ_LEGACY_HOME into the application environment.
    profile=$(grep -m1 -oP '^Path=\K.*' "/home/$user/.mozilla/firefox/profiles.ini")
    dir=/home/$user/.mozilla/firefox/$profile
    as_user certutil -L -d "sql:$dir" | grep -i ficticio
    echo "PROBE import present"

    # Exercise the shipped JRE and the Firefox key imported by the wrapper.
    # Any Java error, timeout, missing signature or invalid signature fails.
    # HOME belongs to the shell started by the user manager.
    # shellcheck disable=SC2016
    in_session sh -c 'printf %s "Baguette signing smoke test." > "$HOME/content.txt"'
    in_session --property=RuntimeMaxSec=60 autofirma sign \
      -i "/home/$user/content.txt" -o "/home/$user/signature.der" \
      -store mozilla -password "" -alias 'ciudadano ficticio' \
      -format cades -config 'mode=explicit' > /tmp/autofirma.log 2>&1 || {
        cat /tmp/autofirma.log
        exit 1
      }
    ${lib.getExe pkgs.openssl} cms -verify -noverify -nointern \
      -certfile "$probe/signer.pem" -inform DER -in "/home/$user/signature.der" \
      -content "/home/$user/content.txt" -binary -out /dev/null
    printf '%s' tampered > /tmp/tampered.txt
    if ${lib.getExe pkgs.openssl} cms -verify -noverify -inform DER \
      -in "/home/$user/signature.der" -content /tmp/tampered.txt -binary -out /dev/null; then
      echo "FAIL: signature accepted tampered content"
      exit 1
    fi
    echo "PROBE signature verified"
  '';
  extraChecks = [
    "home-fs tmpfs$"
    "pfx 644$"
    "ca [1-9][0-9]*$"
    "firefox rendered$"
    "import present$"
    "signature verified$"
  ];
}
