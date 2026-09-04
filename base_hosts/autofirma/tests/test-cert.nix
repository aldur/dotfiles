# A self-signed "citizen" certificate for the tests. A local certificate is
# stable. The fictitious kits from the CAs change without notice.
{ pkgs }:
pkgs.runCommand "autofirma-test-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
  mkdir -p $out
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -sha256 \
    -keyout key.pem -out cert.pem \
    -subj "/C=ES/O=TEST AUTOFIRMA VM/serialNumber=IDCES-00000000T/SN=FICTICIO/GN=CIUDADANO/CN=CIUDADANO FICTICIO - 00000000T" \
    -addext "keyUsage=critical,digitalSignature,nonRepudiation" \
    -addext "extendedKeyUsage=clientAuth,emailProtection"
  openssl pkcs12 -export -out $out/ciudadano.p12 -inkey key.pem -in cert.pem \
    -name "ciudadano ficticio" -passout pass:ficticio
  printf '%s' ficticio > $out/password
''
