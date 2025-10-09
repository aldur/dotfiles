inputs: [
  # https://github.com/iofq/nvim-treesitter-main/tree/master
  inputs.nvim-treesitter-main.overlays.default

  (final: prev: {
    vimPlugins = prev.vimPlugins.extend (f: p: {
      nvim-treesitter = p.nvim-treesitter.withAllGrammars; # or withPlugins...
      # also redefine nvim-treesitter-textobjects (any other plugins that depend on nvim-treesitter)
      nvim-treesitter-textobjects = p.nvim-treesitter-textobjects.overrideAttrs
        (old: { dependencies = [ f.nvim-treesitter ]; });
    });
  })
]
