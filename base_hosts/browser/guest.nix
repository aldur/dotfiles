{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ "${inputs.self}/base_hosts/appliance/guest.nix" ];
  aldur.appliance.application = config.programs.firefox.finalPackage;
  aldur.appliance.state.directories = [ ".config/mozilla" ];
  programs = {
    firefox = {
      enable = true;
      wrapperConfig.speechSynthesisSupport = false;
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisableFirefoxAccounts = true;
        OfferToSaveLogins = false;
        PasswordManagerEnabled = false;
        DontCheckDefaultBrowser = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        ExtensionSettings."*".installation_mode = "blocked";
        Preferences."browser.cache.disk.enable".Value = false;
      };
    };
  };
  environment.sessionVariables.MOZ_CRASHREPORTER_DISABLE = "1";

  # Keep web links in this browser.
  xdg.mime.defaultApplications = lib.genAttrs [
    "text/html"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/about"
    "x-scheme-handler/unknown"
  ] (_: lib.mkForce "firefox.desktop");

}
