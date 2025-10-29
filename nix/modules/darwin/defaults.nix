{ ... }:
{
  system.defaults = {
    dock.autohide = true;
    dock.autohide-delay = 0.0;
    dock.autohide-time-modifier = 0.15;
    dock.mru-spaces = false;

    finder.AppleShowAllExtensions = true;
    # Do not warn on changing file extension
    finder.FXEnableExtensionChangeWarning = false;

    finder.FXPreferredViewStyle = "clmv";

    screencapture.location = "~/Documents/Screenshots";

    screensaver.askForPassword = true;
    screensaver.askForPasswordDelay = 0;

    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    NSGlobalDomain.InitialKeyRepeat = 10;
    NSGlobalDomain.KeyRepeat = 1;

    # ctrl+cmd to drag
    NSGlobalDomain.NSWindowShouldDragOnGesture = true;
    NSGlobalDomain.NSAutomaticWindowAnimationsEnabled = false;

    trackpad.TrackpadThreeFingerDrag = true;

    menuExtraClock = {
      Show24Hour = true;
      ShowAMPM = false;
      ShowDate = 0;
      ShowDayOfWeek = true;
      ShowSeconds = false;
    };

    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

    CustomSystemPreferences = {
      "com.apple.desktopservices" = {
        # Avoid creating .DS_Store files on network or USB volumes
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.AdLib" = {
        allowApplePersonalizedAdvertising = false;
      };
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        # Check for software updates daily, not just once per week
        ScheduleFrequency = 1;
        # Download newly available updates in background
        AutomaticDownload = 1;
        # Install System data files & security updates
        CriticalUpdateInstall = 1;
      };
      # Turn on app auto-update
      "com.apple.commerce".AutoUpdate = true;
    };
  };
}
