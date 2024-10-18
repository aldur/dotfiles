lua require('aldur.lsp')  -- Side effects, autocmds
lua require('aldur.utils').configure_signs()

command! Hover lua vim.lsp.buf.hover()
command! Rename lua vim.lsp.buf.rename()
command! CodeActions lua vim.lsp.buf.code_actions()
