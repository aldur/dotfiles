# Gradle with the Android SDK, to build the Android app in ./android:
#
#   nix run .#avf-ssh-agent-gradle -- -p packages/avf-ssh-agent/app assembleDebug
#
# Gradle gets the dependencies of the app from the network and checks them
# against ./gradle/verification-metadata.xml. Thus this is not a Nix build.
{
  nixpkgs,
  system,
  writeShellApplication,
  gradle_9,
  jdk,
}:
let
  buildTools = "37.0.0";
  # The SDK is unfree. Its licence needs an explicit acceptance.
  unfree = import nixpkgs {
    inherit system;
    config = {
      allowUnfreePredicate = _: true;
      android_sdk.accept_license = true;
    };
  };
  sdk =
    (unfree.androidenv.composeAndroidPackages {
      platformVersions = [ "37" ];
      buildToolsVersions = [ buildTools ];
      includeEmulator = false;
      includeSystemImages = false;
      includeNDK = false;
    }).androidsdk;
in
writeShellApplication {
  name = "avf-ssh-agent-gradle";
  runtimeInputs = [ gradle_9 ];
  text = ''
    export JAVA_HOME=${jdk}
    export ANDROID_HOME=${sdk}/libexec/android-sdk
    # The aapt2 that Gradle gets from Maven does not run on NixOS.
    exec gradle \
      -Dorg.gradle.project.android.aapt2FromMavenOverride="$ANDROID_HOME/build-tools/${buildTools}/aapt2" \
      "$@"
  '';
}
