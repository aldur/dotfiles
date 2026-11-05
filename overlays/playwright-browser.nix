{ pkgs, runtimeLibraries }:
let
  inherit (pkgs.playwright-driver.passthru) browsers-chromium selectBrowsers;
  browsers-headless = selectBrowsers {
    withChromium = false;
    withFirefox = false;
    withWebkit = false;
    withChromiumHeadlessShell = true;
  };
  fontconfig = pkgs.makeFontsConf { fontDirectories = [ ]; };
  # Copy the bundles so locale pruning releases the originals.
  # Keep the signed Chromium bundle intact on Darwin.
  browser =
    if !pkgs.stdenv.hostPlatform.isLinux then
      browsers-chromium
    else
      pkgs.runCommand "playwright-browsers"
        {
          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.patchelf
          ];
          disallowedReferences = map (r: r.oldDependency) runtimeLibraries.chromium;
        }
        ''
          mkdir $out
          for entry in ${browsers-headless}/*; do
            name=''${entry##*/}
            target=$(readlink -f "$entry")
            cp -a "$target" "$out/$name"
            chmod -R u+w "$out/$name"
            { grep -rlF "$target" "$out/$name" || true; } | while IFS= read -r f; do
              [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] && continue
              sed -i "s|$target|$out/$name|g" "$f"
            done
          done
          find $out -type d -name locales | while IFS= read -r d; do
            find "$d" -name '*.pak' ! -name 'en-US.pak' -delete
          done
          ${pkgs.lib.concatMapStringsSep "\n" (r: ''
            find "$out" -type f -exec sed -i "s|${r.oldDependency}|${r.newDependency}|g" {} +
          '') runtimeLibraries.chromium}
          find "$out" -type f | while IFS= read -r f; do
            if patchelf --print-rpath "$f" >/dev/null 2>&1; then
              patchelf --shrink-rpath "$f"
            fi
          done
          # Unlike full Chromium, nixpkgs' shell has no wrapper. Carry
          # over its font and certificate defaults for portable homes.
          # ARM's Playwright bundle uses headless_shell; x86's Chrome
          # for Testing bundle uses chrome-headless-shell.
          shell=$(find $out -type f \( -name chrome-headless-shell -o -name headless_shell \))
          test -x "$shell"
          # The two distributions also package their strings differently.
          # Guard the resources each executable needs after pruning.
          case "''${shell##*/}" in
            headless_shell) test -s "$(dirname "$shell")/headless_lib_strings.pak" ;;
            chrome-headless-shell) test -s "$(dirname "$shell")/locales/en-US.pak" ;;
          esac
          wrapProgram "$shell" \
            --set-default SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
            --set-default FONTCONFIG_FILE ${fontconfig}
          # A leftover would chain a copy back to the full bundle.
          ! grep -r ${browsers-headless} $out
        '';
in
browser
