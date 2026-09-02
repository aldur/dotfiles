# A stand-in "sede": an HTTPS site that loads AutoScript (the JavaScript
# side of AutoFirma) and a page script, plus an endpoint that stores what
# the page reports. Self-contained: the upstream autofirma-nix harness
# downloads its assets from administracionelectronica.gob.es, and those
# links are dead.
{
  # Directory holding autoscript.js; ships in the clienteafirma sources.
  autoscriptDir,
  # The page script; must end by POSTing its result to /result.
  testJs,
  host ? "sede.test",
}:
{ pkgs, lib, ... }:
let
  certs = pkgs.runCommand "${host}-certs" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir -p $out
    cd $out
    cat > san.cnf <<EOF
    [req]
    distinguished_name = dn
    req_extensions = v3_req
    prompt = no
    [dn]
    CN = ${host}
    [v3_req]
    keyUsage = keyEncipherment, dataEncipherment, digitalSignature
    extendedKeyUsage = serverAuth
    subjectAltName = DNS:${host}
    EOF
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt -subj "/CN=${host} test CA"
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -config san.cnf
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
      -out server.crt -days 365 -sha256 -extensions v3_req -extfile san.cnf
    openssl verify -CAfile ca.crt server.crt
    rm ca.key server.csr san.cnf
  '';

  www = pkgs.runCommand "${host}-www" { } ''
    mkdir -p $out
    cp ${testJs} $out/test.js
    cat > $out/index.html <<'EOF'
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>AutoFirma test page</title></head>
    <body>
      <p>Signing this page through AutoFirma…</p>
      <script src="js/autoscript.js"></script>
      <script src="test.js"></script>
    </body>
    </html>
    EOF
  '';

  resultDir = "/var/lib/autofirma-test";

  receiver = pkgs.writers.writePython3Bin "test-result-receiver" { } ''
    from http.server import BaseHTTPRequestHandler, HTTPServer


    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            with open("${resultDir}/result.txt", "ab") as f:
                f.write(body + b"\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")


    HTTPServer(("127.0.0.1", 8081), Handler).serve_forever()
  '';
in
{
  networking.hosts."127.0.0.1" = [ host ];

  security.pki.certificateFiles = [ "${certs}/ca.crt" ];

  services.caddy = {
    enable = true;
    virtualHosts.${host}.extraConfig = ''
      tls ${certs}/server.crt ${certs}/server.key

      handle /result {
        reverse_proxy 127.0.0.1:8081
      }

      handle_path /js/* {
        root * ${autoscriptDir}
        file_server
      }

      handle {
        root * ${www}
        file_server
      }
    '';
  };

  systemd.services.test-result-receiver = {
    description = "Stores what the AutoFirma test page reports";
    wantedBy = [ "multi-user.target" ];
    before = [ "caddy.service" ];
    serviceConfig = {
      ExecStart = lib.getExe receiver;
      StateDirectory = baseNameOf resultDir;
      DynamicUser = true;
    };
  };
}
