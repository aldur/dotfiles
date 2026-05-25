{ pkgs }:
{
  general = {
    LAZYVIM_MD2HTML_ASSETS = "${(pkgs.callPackage ../pandoc_md2html_assets/md2html.nix { })}/assets";
  };
}
