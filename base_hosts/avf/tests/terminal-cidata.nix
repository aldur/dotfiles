# The cidata disk of the Terminal app for x86_64, with the real guest agent
# (linux_vm_manager). It comes from VmTerminalApp.apk in the virt APEX of
# AOSP CI build 16644040 (aosp_cf_x86_64_only_phone-userdebug, Terminal
# CP2A.260605.016). The fetch reads only the APEX from the target files
# archive (2.3 GB), with HTTP range requests.
{
  cacert,
  erofs-utils,
  python3,
  stdenvNoCC,
  unzip,
}:
stdenvNoCC.mkDerivation {
  name = "terminal-cidata-16644040-x86_64.iso";
  nativeBuildInputs = [
    erofs-utils
    python3
    unzip
  ];
  url = "https://ci.android.com/builds/submitted/16644040/aosp_cf_x86_64_only_phone-userdebug/latest/raw/aosp_cf_x86_64_only_phone-target_files-16644040.zip";
  buildCommand = ''
    # Python of Nixpkgs reads this variable before SSL_CERT_FILE.
    export NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    python3 -I ${./zip_member.py} "$url" SYSTEM/apex/com.android.virt.apex virt.apex
    unzip -q virt.apex apex_payload.img
    fsck.erofs --extract=payload apex_payload.img
    unzip -q -p payload/priv-app/VmTerminalApp@*/VmTerminalApp.apk assets/cidata.iso > $out
  '';
  outputHashAlgo = "sha256";
  outputHash = "sha256-Kz4PHwCQ4A8op121YHNJUVJS35iuaFaPuCVnOzEQrZY=";
}
