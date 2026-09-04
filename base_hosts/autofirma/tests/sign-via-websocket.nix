# End-to-end test. The guest boots to the XFCE desktop. Firefox gets a test
# certificate. A page calls AutoScript. Firefox opens the afirma:// handler.
# AutoFirma starts. The page connects to its WebSocket on 127.0.0.1 and gets
# a CAdES signature.
#
# AutoScript comes from the clienteafirma sources. The certificate is
# self-signed and made at build time.
{
  pkgs,
  lib,
  specialArgs,
  guestModule,
  baseModule,
  autofirma-nix,
  # Print what the guest does instead of an assertion. For debugging.
  diagnose ? false,
}:
let
  openssl = lib.getExe pkgs.openssl;

  testCert = import ./test-cert.nix { inherit pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "autofirma-vm-sign-via-websocket";
  enableOCR = diagnose;

  node.specialArgs = specialArgs;
  # The dotfiles base module sets nixpkgs.config and overlays.
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [
      baseModule
      guestModule
      # The guest side of `qemu-vm --file`; the launcher's VM module
      # (autofirma.nix) brings it through nixosModules.qemu-guest.
      "${specialArgs.inputs.self}/modules/nixos/qemu-vm-files.nix"
      (import ./test-server.nix {
        autoscriptDir = "${autofirma-nix.inputs.autofirma-src}/afirma-ui-miniapplet-deploy/src/main/webapp/js";
        testJs = ./websocket-sign.js;
      })
    ];

    # Clicks the button on the page. The test driver has no mouse.
    environment.systemPackages = [ pkgs.xdotool ];

    # The session opens the test page instead of the start page.
    programs.firefox.policies.Homepage.URL = lib.mkForce "https://sede.test/";

    virtualisation = {
      memorySize = 4096;
      cores = 4;
      # What `qemu-vm --file cert.p12=… --file cert.password=…` passes.
      qemu.options = [
        "-fw_cfg name=opt/qemu-vm/cert.p12,file=${testCert}/ciudadano.p12"
        "-fw_cfg name=opt/qemu-vm/cert.password,file=${testCert}/password"
      ];
    };
  }
  // lib.optionalAttrs diagnose {
    # Sends the page console output to the Firefox stdout.
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

      # Take the display and the session bus from the auto-login session.
      # Firefox reaches its running instance over the session bus.
      machine.wait_until_succeeds(f"pgrep -u {USER} -f xfce4-session")
      environ = machine.succeed(
          f"cat /proc/$(pgrep -u {USER} -f xfce4-session | head -n1)/environ | tr '\\0' '\\n'"
      )
      session = dict(
          line.split("=", 1) for line in environ.splitlines() if line.startswith(("DISPLAY=", "XAUTHORITY=", "DBUS_SESSION_BUS_ADDRESS=", "XDG_RUNTIME_DIR="))
      )
      assert "DISPLAY" in session, environ

      def as_user(cmd):
          env = f"HOME=/home/{USER} MOZ_LEGACY_HOME=1 " + " ".join(f"{k}={shlex.quote(v)}" for k, v in session.items())
          return f"runuser -u {USER} -- env {env} sh -c {shlex.quote(cmd)}"

      # The session starts Firefox through autofirma-vm-firefox. That
      # wrapper imports the certificate from the fw_cfg files first.
      machine.wait_for_unit("qemu-vm-files.service")
      machine.succeed(f"test -r /run/qemu-vm-files/cert.p12 && stat -c %U /run/qemu-vm-files/cert.p12 | grep -x {USER}")
      machine.wait_until_succeeds(as_user("certutil -L -d sql:$(dirname ~/.mozilla/firefox/*/cert9.db) | grep -i ficticio"))

      # Firefox opens the test page as its start page. The button on the
      # page opens afirma://. AutoFirma starts, and the page connects to
      # its WebSocket.
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

      # The result is a detached CAdES (CMS) signature over the page text.
      # It must verify against that exact text.
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

      # The root CA must exist only in the guest. That is the purpose of
      # the VM.
      machine.succeed(
          "${openssl} x509 -in /etc/Autofirma/Autofirma_ROOT.cer -noout -subject | grep 'AutoFirma ROOT'"
      )
    '';
}
