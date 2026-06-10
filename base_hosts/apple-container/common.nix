# Shared configuration for the Apple `container` images: the lightweight
# single-process one (`apple-container.nix`, run with `container run`) and the
# full-system one (`apple-machine.nix`, run with `container machine`). Both
# reuse the same NixOS + home-manager evaluation — only how they boot and the
# image entrypoint differ.
{ pkgs, ... }:
{
  # Both run inside Apple's lightweight VM, not on bare metal: no bootloader,
  # kernel or hardware units in the closure.
  boot.isContainer = true;

  # Access is via the `container` runtime (no sshd, no login manager), so no
  # account needs a password; say so rather than be "locked out".
  users.allowNoPasswordLogin = true;

  # Lean toolset, same knobs as the qemu host.
  programs.aldur = {
    lazyvim.enable = true;
    lazyvim.packageNames = [ "lazyvim" ];
    claude-code.enable = true;
  };

  home-manager.users.aldur = _: {
    programs = {
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
    };
  };

  # Apple `container image load` only accepts an OCI archive, while
  # `dockerTools.buildLayeredImage` emits a `docker save`-format one. `regctl`
  # (regclient, a nixpkgs package — no extra Flake input) converts inside the
  # Nix sandbox; unlike skopeo it doesn't need `/var/tmp`, so the build output
  # is loadable directly. `container image load` takes the image name from the
  # index `org.opencontainers.image.ref.name` annotation (split on `:` into
  # name/tag), so we rewrite it to `<name>:latest` and skip a `container image
  # tag` step. Exposed to both image modules as a module argument.
  _module.args.mkOciArchive =
    {
      name,
      layered,
    }:
    pkgs.runCommand "${name}-oci.tar"
      {
        nativeBuildInputs = [
          pkgs.regclient
          pkgs.jq
          pkgs.gnutar
        ];
      }
      ''
        export TMPDIR="$PWD/tmp"
        mkdir -p "$TMPDIR" oci
        regctl image import "ocidir://$PWD/oci:latest" ${layered}
        jq '.manifests[0].annotations["org.opencontainers.image.ref.name"] = "${name}:latest"' \
          oci/index.json > oci/index.json.new
        mv oci/index.json.new oci/index.json
        tar -cf "$out" -C oci .
      '';
}
