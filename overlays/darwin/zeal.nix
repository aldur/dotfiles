(final: prev: {
  zeal-qt6 = prev.zeal-qt6.overrideAttrs (old: {
    installPhase = ''
      runHook preInstall
      APP_DIR="$out/Applications/"
      mkdir -p "$APP_DIR"
      cp -r Zeal.app "$APP_DIR"
      runHook postInstall
    '';
  });
})
