# Private runtime copies: changing the libraries in the package set would
# rebuild their consumers. Instead, repack the cached binaries along the
# three dependency chains that use them in the CLI environment.
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
  vpx = withoutStaticArchives (lib.getLib pkgs.libvpx);
  ffmpegLib = repoint (lib.getLib pkgs.ffmpeg-headless) [
    {
      oldDependency = lib.getLib pkgs.libvpx;
      newDependency = vpx;
    }
  ];
in
{
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
  ffmpeg = repoint (lib.getBin pkgs.ffmpeg-headless) [
    {
      oldDependency = lib.getLib pkgs.ffmpeg-headless;
      newDependency = ffmpegLib;
    }
  ];
}
