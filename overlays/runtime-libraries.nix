# Private runtime copies: changing the libraries in the package set would
# rebuild their consumers. Instead, repack the cached binaries along the
# dependency chains that use them in the CLI environment.
{ pkgs }:
let
  inherit (pkgs) lib;

  repoint =
    drv: replacements:
    (pkgs.replaceDirectDependencies { inherit drv replacements; }).overrideAttrs (_: {
      inherit (drv) meta;
      disallowedReferences = [ drv ] ++ map (r: r.oldDependency) replacements;
    });

  withoutStaticArchives =
    pkg:
    pkgs.runCommand (pkg.name + lib.optionalString (pkg.outputName != "out") "-${pkg.outputName}")
      { disallowedReferences = [ pkg ]; }
      ''
        cp -a ${pkg} "$out"
        chmod -R u+w "$out"
        # Keep the same output name for equal-length binary rewrites.
        find "$out" -type f -exec sed -i "s|${pkg}|$out|g" {} +
        test -n "$(find "$out/lib" -name '*.a' -print -quit)"
        find "$out/lib" -name '*.a' -delete
      '';

  imagequant = withoutStaticArchives pkgs.libimagequant;
  pillow = repoint pkgs.python3.pkgs.pillow [
    {
      oldDependency = pkgs.libimagequant;
      newDependency = imagequant;
    }
  ];
  reportlab = repoint pkgs.python3.pkgs.reportlab [
    {
      oldDependency = pkgs.python3.pkgs.pillow;
      newDependency = pillow;
    }
  ];
  qpdfLib = withoutStaticArchives (lib.getLib pkgs.qpdf);

  # Codex loads these plugins explicitly from its private voice runtime.
  # Keep their shared libraries, without GStreamer's tools, introspection
  # scripts, or unrelated video plugins and their codec dependencies.
  voiceLibrary =
    pkg: libraries: plugins: replacements:
    pkgs.runCommand pkg.name
      {
        nativeBuildInputs = [ pkgs.patchelf ];
        disallowedReferences = [ pkg ] ++ map (r: r.oldDependency) replacements;
      }
      ''
        mkdir -p "$out/lib/gstreamer-1.0"
        ${lib.concatMapStringsSep "\n" (name: ''cp -a ${pkg}/lib/${name}.so* "$out/lib/"'') libraries}
        ${lib.concatMapStringsSep "\n" (
          name: ''cp -a ${pkg}/lib/gstreamer-1.0/libgst${name}.so "$out/lib/gstreamer-1.0/"''
        ) plugins}
        chmod -R u+w "$out"
        find "$out" -type f -exec sed -i "s|${pkg}|$out|g" {} +
        ${lib.concatMapStringsSep "\n" (r: ''
          find "$out" -type f -exec sed -i "s|${r.oldDependency}|${r.newDependency}|g" {} +
        '') replacements}
        find "$out" -type f -exec patchelf --shrink-rpath {} \;
      '';
  gst = pkgs.gst_all_1;
  core = voiceLibrary (lib.getLib gst.gstreamer) [
    "libgstreamer-1.0"
    "libgstbase-1.0"
    "libgstnet-1.0"
  ] [ "coreelements" ] [ ];
  coreReplacement = {
    oldDependency = lib.getLib gst.gstreamer;
    newDependency = core;
  };
  base = voiceLibrary (lib.getLib gst.gst-plugins-base) [
    "libgstapp-1.0"
    "libgstaudio-1.0"
    "libgstpbutils-1.0"
    "libgsttag-1.0"
    "libgstvideo-1.0"
    "libgstrtp-1.0"
    "libgstfft-1.0"
    "libgstallocators-1.0"
  ] [ "app" "audioconvert" "audioresample" "opus" ] [ coreReplacement ];
  baseReplacement = {
    oldDependency = lib.getLib gst.gst-plugins-base;
    newDependency = base;
  };
  good =
    voiceLibrary (lib.getLib gst.gst-plugins-good) [ ]
      [ "rtp" "rtpmanager" ]
      [ coreReplacement baseReplacement ];
in
{
  codexVoice = [
    coreReplacement
    baseReplacement
    {
      oldDependency = lib.getLib gst.gst-plugins-good;
      newDependency = good;
    }
  ];

  # Python wrappers embed the complete module path, so replace both the
  # immediate dependency (ReportLab) and its transitive dependency (Pillow).
  watermark-pdf = repoint pkgs.watermark-pdf [
    {
      oldDependency = pkgs.python3.pkgs.pillow;
      newDependency = pillow;
    }
    {
      oldDependency = pkgs.python3.pkgs.reportlab;
      newDependency = reportlab;
    }
  ];
  qpdf = repoint (lib.getBin pkgs.qpdf) [
    {
      oldDependency = lib.getLib pkgs.qpdf;
      newDependency = qpdfLib;
    }
  ];
}
