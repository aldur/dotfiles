# What only the Baguette image needs, on top of crostini.nix. The LXC
# container does not import this file.
{ ... }:
{
  virtualisation.buildMemorySize = 1024 * 8;
  virtualisation.diskImageSize = 1024 * 16;

  # -- Size -------------------------------------------------------------------
  # No /run/opengl-driver: mesa and its LLVM take 800 MiB. The sommelier
  # of ChromeOS brings its own libraries on the tools disk. Programs render
  # in software.
  hardware.graphics.enable = false;
}
