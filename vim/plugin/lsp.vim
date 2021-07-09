autocmd vimrc User LspDiagnosticsChanged call lightline#update()
autocmd vimrc User LspDiagnosticsChanged lua vim.lsp.diagnostic.set_loclist({open_loclist = false})
