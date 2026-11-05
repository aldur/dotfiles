{
  lib,
  writeText,
  writeShellApplication,
  playwright-mcp,
  playwright-driver,
  stdenv,
  coreutils,
}:
let
  # Keep the identity claims in sync with the pinned browser build.
  major = lib.versions.major
    playwright-driver.passthru.browsersJSON."chromium-headless-shell".browserVersion;

  isDarwin = stdenv.hostPlatform.isDarwin;
  uaPlatform =
    if isDarwin then "Macintosh; Intel Mac OS X 10_15_7"
    else "X11; Linux ${if stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64"}";
  chPlatform = if isDarwin then "\"macOS\"" else "\"Linux\"";
  # "Not.A/Brand" is Chromium's GREASE slot; it rotates between releases.
  secChUa = "\"Chromium\";v=\"${major}\", \"Not.A/Brand\";v=\"8\", \"Google Chrome\";v=\"${major}\"";

  # Runs in every page before page scripts. Hides what launch flags cannot:
  # the JS-readable user-agent data and the headless-shell plugin gaps.
  initScript = writeText "pi-browser-init.js" ''
    (() => {
      const swap = (brand) =>
        brand.startsWith("Headless") ? "Google Chrome" : brand;
      const data = navigator.userAgentData;
      if (data && data.brands.some((brand) => brand.brand.startsWith("Headless"))) {
        const proto = Object.getPrototypeOf(data);
        const brands = data.brands.map((brand) => ({
          brand: swap(brand.brand),
          version: brand.version,
        }));
        Object.defineProperty(proto, "brands", {
          configurable: true,
          get: () => brands,
        });
        const original = proto.getHighEntropyValues;
        proto.getHighEntropyValues = async (hints) => {
          const values = await original.call(data, hints);
          if (values.fullVersionList)
            values.fullVersionList = values.fullVersionList.map((brand) => ({
              brand: swap(brand.brand),
              version: brand.version,
            }));
          return values;
        };
      }
      if (!window.chrome) window.chrome = { runtime: {} };
      if (navigator.plugins.length === 0) {
        const mimes = [
          {
            type: "application/pdf",
            suffixes: "pdf",
            description: "Portable Document Format",
          },
          { type: "text/pdf", suffixes: "pdf", description: "Portable Document Format" },
        ];
        const names = [
          "PDF Viewer",
          "Chrome PDF Viewer",
          "Chromium PDF Viewer",
          "Microsoft Edge PDF Viewer",
          "WebKit built-in PDF",
        ];
        const list = (entries, key) => ({
          length: entries.length,
          item: (index) => entries[index] ?? null,
          namedItem: (name) => entries.find((entry) => key(entry) === name) ?? null,
          [Symbol.iterator]: entries[Symbol.iterator].bind(entries),
          ...Object.fromEntries(entries.map((entry, index) => [index, entry])),
        });
        const plugins = names.map((name) => ({
          name,
          filename: "internal-pdf-viewer",
          description: "Portable Document Format",
          ...list(mimes, (mime) => mime.type),
        }));
        for (const mime of mimes) mime.enabledPlugin = plugins[0];
        Object.defineProperty(navigator, "plugins", {
          configurable: true,
          get: () => list(plugins, (plugin) => plugin.name),
        });
        Object.defineProperty(navigator, "mimeTypes", {
          configurable: true,
          get: () => list(mimes, (mime) => mime.type),
        });
      }
    })();
  '';

  config = writeText "pi-browser.json" (builtins.toJSON {
    browser = {
      launchOptions = {
        chromiumSandbox = true;
        # Playwright passes this switch by default; it sets navigator.webdriver.
        ignoreDefaultArgs = [ "--enable-automation" ];
        args = [ "--disable-blink-features=AutomationControlled" ];
      };
      initScript = [ initScript ];
      contextOptions = {
        acceptDownloads = true;
        viewport = {
          width = 1440;
          height = 900;
        };
        locale = "en-US";
        colorScheme = "light";
        # The headless shell announces itself as HeadlessChrome in both the
        # UA header and the low-entropy client hints; speak like desktop Chrome.
        userAgent = "Mozilla/5.0 (${uaPlatform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${major}.0.0.0 Safari/537.36";
        extraHTTPHeaders = {
          "Sec-CH-UA" = secChUa;
          "Sec-CH-UA-Mobile" = "?0";
          "Sec-CH-UA-Platform" = chPlatform;
        };
      };
    };
  });
in
writeShellApplication {
  name = "pi-browser-mcp";
  runtimeInputs = [ coreutils ];
  text = ''
    umask 077
    mkdir -p "$PWD/.pi/browser"
    output=$(mktemp -d "$PWD/.pi/browser/worker-XXXXXXXX")
    exec ${lib.getExe playwright-mcp} \
      --config ${config} --headless --isolated --output-dir "$output"
  '';
}
