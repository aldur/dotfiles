autocmd vimrc User LspDiagnosticsChanged call lightline#update()
autocmd vimrc User LspDiagnosticsChanged lua vim.lsp.diagnostic.set_loclist({open_loclist = false})

command! Hover lua vim.lsp.buf.hover()
command! Rename lua vim.lsp.buf.rename()
