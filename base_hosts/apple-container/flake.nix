{
  description = "A NixOS OCI image for Apple `container` (run + machine), from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };
  };
  outputs =
    { aldur-dotfiles, ... }@inputs:
    let
      specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils home-manager;

      # One image serves both: `container run` uses the OCI entrypoint, while
      # `container machine` execs /sbin/init. Same closure, two entry doors.
      cfg =
        system:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            aldur-dotfiles.nixosModules.default
            ./configuration.nix
          ];
        };

      minimal =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            (nixpkgs + "/nixos/modules/profiles/minimal.nix")
            ./apple-container.nix
            {
              system.stateVersion = nixpkgs.lib.trivial.release;
              virtualisation.appleContainer = {
                username = "nixos";
                imageName = "nixos";
              };
              users.users.nixos.extraGroups = [ "wheel" ];
              nix.settings.experimental-features = [
                "nix-command"
                "flakes"
              ];
            }
          ];
        };

      # `minimal` plus home-manager, so the entrypoint test exercises every
      # activation stage.
      entrypointTest =
        system:
        (minimal system).extendModules {
          modules = [
            home-manager.nixosModules.home-manager
            { home-manager.users.nixos.home.stateVersion = nixpkgs.lib.trivial.release; }
          ];
        };
    in
    # The image is always a Linux artifact. On a Darwin host (the usual case —
    # Apple silicon) map to the matching linux system so `#container-image`
    # works directly and offloads to the user's Linux builder. Building the
    # aarch64 image natively needs an aarch64 builder.
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        targetSystem =
          {
            aarch64-darwin = "aarch64-linux";
            x86_64-darwin = "x86_64-linux";
          }
          .${system} or system;
      in
      {
        packages = rec {
          container-image = (cfg targetSystem).config.system.build.containerImage;
          minimal-image = (minimal targetSystem).config.system.build.containerImage;
          default = container-image;
        };

        checks.entrypoint-fails-closed = import ./entrypoint-test.nix {
          nixos = entrypointTest targetSystem;
        };

        # Build + load in one step: the image is the script's dependency, so
        # `nix run` realizes it (offloading to the Linux builder on Darwin)
        # and then hands it to Apple's CLI.
        apps =
          let
            pkgs = nixpkgs.legacyPackages.${system};
            mkLoad =
              image:
              let
                script = pkgs.writeShellScript "load-${image.name}" ''
                  if ! command -v container >/dev/null 2>&1; then
                    echo "error: Apple's \`container\` CLI not found in PATH" >&2
                    exit 1
                  fi
                  exec container image load --input ${image}
                '';
              in
              {
                type = "app";
                program = "${script}";
              };
            mkPush =
              c:
              let
                image = c.config.system.build.containerImage;
                name = c.config.virtualisation.appleContainer.imageName;
              in
              {
                type = "app";
                program = "${pkgs.writeShellScript "push-${name}" ''
                  set -eu
                  repo="''${1:-ghcr.io/aldur}"
                  tag="''${2:-latest}"
                  # The third argument names a file. skopeo writes the digest
                  # of the pushed manifest to it. CI attests that digest.
                  digestfile="''${3:-}"
                  args=()
                  if [ -n "$digestfile" ]; then
                    args+=(--digestfile "$digestfile")
                  fi
                  echo "pushing ${name} -> $repo/${name}:$tag"
                  exec ${nixpkgs.lib.getExe pkgs.skopeo} copy "''${args[@]}" \
                    oci-archive:${image} "docker://$repo/${name}:$tag"
                ''}";
              };
            # Stitch the per-arch tags that CI pushes (`:latest-amd64`,
            # `:latest-arm64`) into a multi-arch `:latest` manifest list.
            # regctl reads each ref's platform from its config, so we needn't
            # name platforms here. Pure registry work — no image is realised —
            # so any one runner can run it, and it's cheap.
            mkManifest =
              c:
              let
                name = c.config.virtualisation.appleContainer.imageName;
              in
              {
                type = "app";
                program = "${pkgs.writeShellScript "manifest-${name}" ''
                  set -eu
                  repo="''${1:-ghcr.io/aldur}"
                  tag="''${2:-latest}"
                  img="$repo/${name}"
                  # The third argument names a file. The script writes the
                  # digest of the new index to it. CI attests that digest.
                  digestfile="''${3:-}"
                  echo "assembling $img:$tag from :$tag-amd64 + :$tag-arm64"
                  ${pkgs.regclient}/bin/regctl index create "$img:$tag" \
                    --ref "$img:$tag-amd64" \
                    --ref "$img:$tag-arm64"
                  # A HEAD request without a platform returns the digest of
                  # the index itself, not of one of its images.
                  digest=$(${pkgs.regclient}/bin/regctl image digest "$img:$tag")
                  echo "$img:$tag -> $digest"
                  if [ -n "$digestfile" ]; then
                    printf '%s\n' "$digest" > "$digestfile"
                  fi
                ''}";
              };
            mkSbom =
              c:
              aldur-dotfiles.lib.mkSbomApp {
                inherit pkgs;
                configuration = c;
                name = c.config.virtualisation.appleContainer.imageName;
              };
          in
          rec {
            load = mkLoad (cfg targetSystem).config.system.build.containerImage;
            load-minimal = mkLoad (minimal targetSystem).config.system.build.containerImage;
            default = load;

            # Build (if needed) and push one image to a registry.
            # `nix run …#push` → ghcr.io/aldur:latest; override repo and tag:
            # `nix run …#push -- ghcr.io/someone-else latest-amd64`. Auth:
            # anything skopeo understands — `skopeo login ghcr.io -u <user>`
            # or an existing `docker login` (a GH token with write:packages).
            # NB: pushes the arch you build on — aarch64 from a Mac. CI runs
            # this on a native runner per arch into `:latest-<arch>` tags,
            # then `manifest` stitches them into a multi-arch `:latest`.
            push = mkPush (cfg targetSystem);
            push-minimal = mkPush (minimal targetSystem);

            # Assemble the multi-arch `:latest` from the per-arch tags above.
            # Registry-only, so it runs on any one runner after both pushes.
            manifest = mkManifest (cfg targetSystem);
            manifest-minimal = mkManifest (minimal targetSystem);

            # Write the SBOM of the system in the image to a directory:
            # `nix run …#sbom -- ./sbom`. CI attests it to the pushed image.
            sbom = mkSbom (cfg targetSystem);
            sbom-minimal = mkSbom (minimal targetSystem);
          };
      }
    )
    // {
      # The generic part — anyone can import this into their own
      # nixosConfiguration (no dependency on aldur's dotfiles) and build
      # `config.system.build.containerImage`. See the
      # `virtualisation.appleContainer` options in apple-container.nix.
      nixosModules = rec {
        apple-container = ./apple-container.nix;
        default = apple-container;
      };

      nixosConfigurations = {
        apple-container = cfg "aarch64-linux";
        apple-container-aarch64 = cfg "aarch64-linux";
        apple-container-x86_64 = cfg "x86_64-linux";
      };
    };
}
