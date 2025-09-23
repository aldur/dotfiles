-- Disable automatic yanking to clipboard
vim.opt.clipboard = ''

-- Disable animations
vim.g.snacks_animate = false

-- We use `basedpyright`
vim.g.lazyvim_python_lsp = 'basedpyright'

-- Fuzzy completion
vim.opt.completeopt:append { 'fuzzy' }
