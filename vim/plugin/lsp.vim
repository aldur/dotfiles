autocmd vimrc User LspDiagnosticsChanged call lightline#update()

" Inspired by how lightline.vim refreshes the statusline.
autocmd vimrc WinEnter,BufEnter,SessionLoadPost * lua vim.lsp.diagnostic.set_loclist({open_loclist = false})
autocmd vimrc User LspDiagnosticsChanged lua vim.lsp.diagnostic.set_loclist({open_loclist = false})

command! Hover lua vim.lsp.buf.hover()
command! Rename lua vim.lsp.buf.rename()
