{
  pkgs,
  toplevel,
  regInfo,
  compress ? false,
  compressor ? "lz4hc,level=12",
}:
# Compression requires Linux 6.1 or later with CONFIG_EROFS_FS_ZIP=y.
# Deduplication requires one mkfs worker.
pkgs.runCommand "nix-store-image"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.erofs-utils
    ];
  }
  ''
    mkdir -p $out
    tar --create \
      --absolute-names \
      --verbatim-files-from \
      --transform 'flags=rSh;s|/nix/store/||' \
      --transform 'flags=rSh;s|~nix~case~hack~[[:digit:]]\+||g' \
      --files-from ${
        pkgs.closureInfo {
          rootPaths = [
            toplevel
            regInfo
          ];
        }
      }/store-paths \
      | mkfs.erofs \
        --quiet \
        --workers=${if compress then "1" else "\${NIX_BUILD_CORES:-1}"} \
        ${pkgs.lib.optionalString compress "-z${pkgs.lib.escapeShellArg compressor} -C65536 -Efragments,ztailpacking,dedupe"} \
        --force-uid=0 \
        --force-gid=0 \
        -L nix-store \
        -U eb176051-bd15-49b7-9e6b-462e0b467019 \
        -T 0 \
        --hard-dereference \
        --tar=f \
        $out/store.img

    ${pkgs.lib.optionalString compress ''
      # Check all file data without extraction to disk.
      fsck.erofs --extract $out/store.img
    ''}
  ''
