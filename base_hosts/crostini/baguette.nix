# What only the Baguette image needs, on top of crostini.nix. The LXC
# container does not import this file.
{ ... }:
{
  virtualisation.buildMemorySize = 1024 * 8;
  virtualisation.diskImageSize = 1024 * 16;
}
