{
  pkgs,
  home-manager,
  baseHome,
  lazyvim-light,
  dotfiles,
  uid,
  mkOciArchive,
}:
let
  inherit (pkgs) lib;
  runtime = import ./runtime.nix { inherit pkgs dotfiles; };
  tinyPkgs = pkgs.extend (
    _: prev: {
      inherit (runtime) fish pi moreutils;
    }
  );
  home = home-manager.lib.homeManagerConfiguration {
    pkgs = tinyPkgs;
    extraSpecialArgs = {
      inherit baseHome lazyvim-light dotfiles;
      profile = "minimal";
      runtimePython = runtime.python;
    };
    modules = [ ./home.nix ];
  };
  inherit (home.config.home) username homeDirectory;
  homePath = lib.removePrefix "/" homeDirectory;
  name = "aldur-pi";
  entrypoint = pkgs.callPackage ./pi-container.nix {
    homeFiles = home.config.home-files;
    homeProfile = home.config.home.path;
    piConfigSync = home.config.programs.pi.configSync;
  } uid;
  root = pkgs.buildEnv {
    name = "pi-container-root";
    paths = [
      (lib.hiPrio home.config.home.path)
      entrypoint
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.findutils
      pkgs.diffutils
    ];
    pathsToLink = [ "/bin" ];
    ignoreCollisions = true;
    postBuild = ''
      ln -s ${lib.getExe lazyvim-light} "$out/bin/lazyvim"
      ln -s ${lib.getExe lazyvim-light} "$out/bin/nvim"
    '';
  };
  closure = pkgs.writeText "pi-container-closure" (
    lib.concatStringsSep "\n" (
      map toString [
        root
        home.config.home-files
        pkgs.cacert
        pkgs.ncurses
      ]
    )
  );
  stream = pkgs.dockerTools.streamLayeredImage {
    inherit name;
    tag = "latest";
    contents = [ root ];
    maxLayers = 2;
    extraCommands = ''
      mkdir -p dev proc sys etc ${homePath} workspace tmp var/tmp var/host-services usr/bin
      cp -a ${home.config.home-files}/. ${homePath}/
      find ${homePath} -type d -exec chmod u+w {} +
      ln -s ${home.config.home.path} ${homePath}/.nix-profile
      ln -s ${pkgs.coreutils}/bin/env usr/bin/env
      printf 'root:x:0:0:root:/root:/bin/sh\n${username}:x:${toString uid}:100::${homeDirectory}:/bin/fish\n' > etc/passwd
      printf 'root:x:0:\nusers:x:100:\n' > etc/group
      printf 'passwd: files\ngroup: files\nhosts: files dns\n' > etc/nsswitch.conf
      printf '127.0.0.1 localhost\n' > etc/hosts
      : > etc/resolv.conf
      printf 'NAME="Pi sandbox"\nID=pi-sandbox\n' > etc/os-release
      chmod 1777 tmp var/tmp
    '';
    fakeRootCommands = ''
      chown -R ${toString uid}:100 ./${homePath} ./workspace
    '';
    config = {
      Entrypoint = [ (lib.getExe entrypoint) ];
      WorkingDir = "/workspace";
      Env = [
        "PATH=/bin"
        "HOME=${homeDirectory}"
        "USER=${username}"
        "LOGNAME=${username}"
        "SHELL=/bin/fish"
        "TERM=xterm-256color"
        "LANG=C.UTF-8"
        "EDITOR=${home.config.home.sessionVariables.EDITOR}"
        "VISUAL=${home.config.home.sessionVariables.VISUAL}"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "TERMINFO_DIRS=${pkgs.ncurses}/share/terminfo"
      ];
    };
  };
  image = mkOciArchive {
    inherit name stream;
    compressionLevel = 22;
  };

in
{
  inherit image closure name;
}
