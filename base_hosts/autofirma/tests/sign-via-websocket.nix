# End-to-end: the guest boots to the XFCE desktop, Firefox gets a test
# certificate, a page calls AutoScript, Firefox opens the afirma:// handler,
# AutoFirma starts, the page connects to its WebSocket on 127.0.0.1 and a
# CAdES signature comes back.
#
# AutoScript comes from the clienteafirma sources; the certificate is a
# self-signed one made at build time.
{
  pkgs,
  lib,
  specialArgs,
  guestModule,
  baseModule,
  autofirma-nix,
  # Print what the guest does instead of asserting; for debugging.
  diagnose ? false,
}:
let
  openssl = lib.getExe pkgs.openssl;

  # A self-signed "citizen" certificate. Deterministic assets beat a
  # download: the fictitious kits the CAs publish change without notice.
  testCert = pkgs.runCommand "autofirma-test-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir -p $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 -sha256 \
      -keyout key.pem -out cert.pem \
      -subj "/C=ES/O=TEST AUTOFIRMA VM/serialNumber=IDCES-00000000T/SN=FICTICIO/GN=CIUDADANO/CN=CIUDADANO FICTICIO - 00000000T" \
      -addext "keyUsage=critical,digitalSignature,nonRepudiation" \
      -addext "extendedKeyUsage=clientAuth,emailProtection"
    openssl pkcs12 -export -out $out/ciudadano.p12 -inkey key.pem -in cert.pem \
      -name "ciudadano ficticio" -passout pass:
  '';
in
pkgs.testers.runNixOSTest {
  name = "autofirma-vm-sign-via-websocket";
  enableOCR = diagnose;

  node.specialArgs = specialArgs;
  # The dotfiles base module sets nixpkgs.config and overlays itself.
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [
      baseModule
      guestModule
      (import ./test-server.nix {
        autoscriptDir = "${autofirma-nix.inputs.autofirma-src}/afirma-ui-miniapplet-deploy/src/main/webapp/js";
        testJs = ./websocket-sign.js;
      })
    ];

    # Clicks the page's button; the test driver has no mouse.
    environment.systemPackages = [ pkgs.xdotool ];

    virtualisation = {
      memorySize = 4096;
      cores = 4;
    };
  }
  // lib.optionalAttrs diagnose {
    # Page console output lands in Firefox's stdout.
    programs.firefox.autoConfig = lib.mkAfter ''
      pref("devtools.console.stdout.content", true);
      pref("browser.dom.window.dump.enabled", true);
    '';
  };

  testScript =
    { nodes, ... }:
    ''
      import shlex

      USER = "${nodes.machine.mainUser}"

      machine.wait_for_unit("graphical.target")
      machine.wait_for_unit("create-autofirma-cert.service")
      machine.wait_for_open_port(443)

      # The auto-login session; take DISPLAY and XAUTHORITY from it.
      machine.wait_until_succeeds(f"pgrep -u {USER} -f xfce4-session")
      environ = machine.succeed(
          f"cat /proc/$(pgrep -u {USER} -f xfce4-session | head -n1)/environ | tr '\\0' '\\n'"
      )
      session = dict(
          line.split("=", 1) for line in environ.splitlines() if line.startswith(("DISPLAY=", "XAUTHORITY="))
      )
      assert "DISPLAY" in session, environ

      def as_user(cmd):
          env = f"HOME=/home/{USER} MOZ_LEGACY_HOME=1 " + " ".join(f"{k}={shlex.quote(v)}" for k, v in session.items())
          return f"runuser -u {USER} -- env {env} sh -c {shlex.quote(cmd)}"

      # First start creates the profile and its NSS database.
      machine.execute(as_user("firefox >/tmp/firefox.log 2>&1 &"))
      machine.wait_until_succeeds(as_user("ls ~/.mozilla/firefox/*/cert9.db"))
      machine.wait_until_succeeds(as_user("ls ~/.mozilla/firefox/*/key4.db"))
      machine.sleep(5)
      machine.succeed(f"pkill -u {USER} firefox; sleep 3; true")

      # Import the fictitious citizen certificate the way the user would.
      machine.succeed(as_user('import-certificate ${testCert}/ciudadano.p12 ""'))
      machine.succeed(as_user("certutil -L -d sql:$(dirname ~/.mozilla/firefox/*/cert9.db) | grep -i ficticio"))

      # The page's button triggers afirma:// → AutoFirma → WebSocket → signature.
      machine.execute(as_user("firefox --new-tab https://sede.test/ >>/tmp/firefox.log 2>&1 &"))
      machine.wait_until_succeeds(as_user("xdotool search --name 'AutoFirma test page'"))
      machine.sleep(5)
      machine.succeed(as_user(
          "id=$(xdotool search --name 'AutoFirma test page' | head -n1);"
          " xdotool windowactivate --sync $id; xdotool mousemove --window $id 400 400 click 1"
      ))
      ${
        if diagnose then
          ''
            for i in range(8):
                machine.sleep(20)
                print(f"===== round {i}")
                print(machine.execute("ps -u " + USER + " -o pid,etimes,cmd | grep -iv 'contentproc\\|grep' | cut -c1-180; echo == FFLOG; tail -n 20 /tmp/firefox.log; echo == CADDY; journalctl -u caddy --no-pager -o cat | tail -n 15; echo == RESULT; ls -la /var/lib/autofirma-test; cat /var/lib/autofirma-test/result.txt; echo == AFIRMA; ls -la /home/" + USER + "/.afirma /etc/Autofirma; cat /home/" + USER + "/.afirma/*.log 2>/dev/null | tail -n 40")[1])
                print("== SCREEN\n" + machine.get_screen_text())
                if i == 2:
                    print("== launching afirma:// from the command line")
                    machine.execute(as_user("firefox 'afirma://sign?op=sign&algorithm=SHA256withRSA&format=AUTO' >>/tmp/firefox.log 2>&1 &"))
                if machine.execute("test -s /var/lib/autofirma-test/result.txt")[0] == 0:
                    break
          ''
        else
          ''
            machine.wait_for_file("/var/lib/autofirma-test/result.txt", timeout=300)
          ''
      }
      machine.sleep(5)
      machine.screenshot("desktop")
      output = machine.succeed("cat /var/lib/autofirma-test/result.txt")
      print(output[:200])
      assert output.startswith("Signature Successful: "), output

      # A detached CAdES (CMS) signature by the test certificate over the
      # page's text: the signature must verify against that exact text.
      signature = output[len("Signature Successful: "):].strip()
      machine.succeed(f"echo {shlex.quote(signature)} | base64 -d > /tmp/signature.der")
      machine.succeed("printf '%s' 'Signed from the AutoFirma VM test page.' > /tmp/content.txt")
      machine.succeed(
          "${openssl} cms -verify -noverify -inform DER -in /tmp/signature.der"
          " -content /tmp/content.txt -binary -out /dev/null"
      )
      machine.fail(
          "printf '%s' 'tampered' > /tmp/other.txt; ${openssl} cms -verify -noverify -inform DER"
          " -in /tmp/signature.der -content /tmp/other.txt -binary -out /dev/null"
      )
      machine.succeed(
          "${openssl} pkcs7 -inform DER -in /tmp/signature.der -print_certs -noout | grep 'CIUDADANO FICTICIO'"
      )

      # The point of the VM: the generated root CA exists only in the guest.
      machine.succeed(
          "${openssl} x509 -in /etc/Autofirma/Autofirma_ROOT.cer -noout -subject | grep 'AutoFirma ROOT'"
      )
    '';
}
