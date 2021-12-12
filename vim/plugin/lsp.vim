autocmd vimrc DiagnosticChanged * call lightline#update()

" Inspired by how lightline.vim refreshes the statusline.
autocmd vimrc WinEnter,BufEnter,SessionLoadPost * lua vim.diagnostic.setloclist({open = false})
autocmd vimrc DiagnosticChanged * lua vim.diagnostic.setloclist({open = false})
lua require('plugins/trouble')

command! Hover lua vim.lsp.buf.hover()
command! Rename lua vim.lsp.buf.rename()

command! ToggleVirtualText call aldur#lsp#toggle_virtual_text()
command! ToggleSigns call aldur#lsp#toggle_signs()
