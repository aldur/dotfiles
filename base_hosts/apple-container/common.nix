{ pkgs, ... }:
{
  boot.isContainer = true;
  users.allowNoPasswordLogin = true;

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

  _module.args.mkOciArchive =
    {
      name,
      stream,
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
        ${stream} > "$TMPDIR/image.tar"
        regctl image import "ocidir://$PWD/oci:latest" "$TMPDIR/image.tar"
        rm -f "$TMPDIR/image.tar"
        jq '.manifests[0].annotations["org.opencontainers.image.ref.name"] = "${name}:latest"' \
          oci/index.json > oci/index.json.new
        mv oci/index.json.new oci/index.json
        tar -cf "$out" -C oci .
      '';
}
