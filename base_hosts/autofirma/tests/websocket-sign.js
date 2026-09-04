// Page script for tests/sign-via-websocket.nix.
//
// On a desktop browser, AutoScript uses its WebSocket client. Firefox opens
// afirma://. AutoFirma starts a TLS WebSocket server on 127.0.0.1. The page
// connects to it. Note: `setForceWSMode` does not select this mode. There,
// "WS" means the web service relay through the storage and retriever
// servlets.
//
// The page reports the result, good or bad, to /result. The test reads it
// there.
//
// A click on a full-page button starts the signature. Firefox opens an
// external protocol from an iframe (the AutoScript method) only after a
// user gesture. A real sede also puts the signature behind a button.
(function () {
  function report(message) {
    console.log(message);
    fetch("/result", { method: "POST", body: message });
  }

  function sign() {
    AutoScript.cargarAppAfirma();

    // Base64 of ASCII text. btoa() rejects characters outside Latin-1.
    var data = btoa("Signed from the AutoFirma VM test page.");
    try {
      AutoScript.sign(
        data,
        "SHA256withRSA",
        "CAdES",
        "headless=true",
        function (signature) {
          report("Signature Successful: " + signature);
        },
        function (type, message) {
          report("Error (" + type + "): " + message);
        },
      );
    } catch (error) {
      report("Error (Exception): " + error.message);
    }
  }

  window.addEventListener("DOMContentLoaded", function () {
    var button = document.createElement("button");
    button.id = "sign";
    button.textContent = "Firmar";
    button.style.cssText =
      "position:fixed;inset:0;width:100%;height:100%;font-size:48px;";
    button.addEventListener("click", function () {
      button.disabled = true;
      button.textContent = "Firmando…";
      sign();
    });
    document.body.appendChild(button);
  });
})();
