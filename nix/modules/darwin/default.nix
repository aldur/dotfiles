{
  config,
  user,
  lib,
  ...
}:
{
  imports = [
    ./homebrew.nix
    ./launchd/ollama.nix
    ./launchd/open-webui.nix
    ./launchd/syncthing.nix
    ./security.nix
    ./defaults.nix
  ];

  nix.settings = {
    sandbox = false; # On macOS, sandbox doesn't play well :(
  };

  users.users.${user} = {
    home = "/Users/${user}";
  };

  # Used for backwards compatibility. please read the changelog
  # before changing: `darwin-rebuild changelog`.
  system.stateVersion = 6;

  system.activationScripts.postActivation.text =
    let
      home = config.users.users.aldur.home;
    in
    lib.mkBefore ''
      # Configure TimeMachine exclusions
      # WARNING: This will _not_ remove exclusions, do it manually if you need to with
      # sudo tmutil removeexclusion -p <path>

      # WARNING: This will wail if your terminal doesn't have full disk access.
      sudo tmutil addexclusion -p \
      "${home}/Virtual Machines.localized"  \
       "${home}/Library/Containers/com.docker.docker" \
       \
       "${home}/Downloads" \
       "${home}/Pictures" \
       \
       "${home}/.ollama" \
       "${home}/.diffusionbee" \
       "${home}/Application Support/io.datasette.llm" \
       \
       "${home}/.cache" \
       "${home}/.cargo" \
       "${home}/.vim_backups/tags" \
       "${home}/.npm" \
       \
       "${home}/Library/Application Support/Zeal" \
       "${home}/Library/Application Support/Caches" \
       \
       "${home}/Library/pnpm" \
       "${home}/Library/Developer" \
       || true

      # find ${home}/Work -type d \( \
      #   -name '.venv' \
      #   -o -name '.tox' \
      #   -o -name 'node_modules' \
      #   -o -name 'target' \
      #   -o -name '.terraform' \) \
      #   -exec sudo tmutil addexclusion -p "{}" +

      # Check the result with 
      #   defaults read /Library/Preferences/com.apple.TimeMachine SkipPaths
      # https://alexwlchan.net/til/2024/exclude-files-from-time-machine-with-tmutil/
    ''
    # Once this merges, the following shouldn't be necessary:
    # https://github.com/nix-darwin/nix-darwin/pull/1396
    + ''
      (
      	existingPaths="$(/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -e "path: */nix/" | sed -E 's/.*(\/nix\/.*) \(0x[0-9a-f]+\)/\1/')"
      	IFS=$'\n'
      	for i in $existingPaths; do
      		echo "Unregistering application $i"
      		"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -u "$i"
      	done
      )

      # Delete Launchpad DB
      echo "Deleting Launchpad DB"
      rm /private"$(sudo --user ${config.system.primaryUser} getconf DARWIN_USER_DIR)"com.apple.dock.launchpad/db/db{,-shm,-wal}

      # Register new apps
      find /Applications/Nix\ Apps/ -name "*.app" -exec sh -c 'echo "Registering application $1" && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(readlink -f "$1")' sh {} \;

      killall Dock
    '';
}
