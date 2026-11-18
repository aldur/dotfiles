# The kernel, the initramfs and the VM configuration of the Debian image of
# the Terminal app, for x86_64. The app boots its guest with these files.
# The archive also has the Debian root (3 GB), which this does not keep.
{ fetchurl }:
fetchurl {
  name = "ferrochrome-5100000-x86_64";
  url = "https://dl.google.com/android/ferrochrome/5100000/x86_64/images.tar.gz";
  downloadToTemp = true;
  recursiveHash = true;
  postFetch = ''
    mkdir $out
    tar -xzf "$downloadedFile" -C $out build_id vm_config.json vmlinuz initrd.img
  '';
  hash = "sha256-NmJKQQAJixFdn2mR0K+pM3Q1QdKMeyc+2Y0aohgaJmg=";
}
