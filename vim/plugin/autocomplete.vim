" set complete+=k
" set complete+=kspell
set completeopt=menuone,noselect

" This enables Dictionary completion in deoplete
" In standard VIM completion,this should not be required as it defaults to the
" spell files (if enabled), but `deoplete-dictionary` cannot parse those
" files, so we make it default to macOS words.
" Disabled, simply `setlocal` it in a buffer to enable completion.
" set dictionary+=/usr/share/dict/words

set shortmess+=c " Quiet completions

lua require('plugins/nvim-lspconfig')
lua require('plugins/compe')

" inoremap <silent><expr> <Tab> compe#complete()
" inoremap <silent><expr> <CR>      compe#confirm({'keys': "\<Plug>(PearTreeExpand)", 'mode': ''})
" inoremap <silent><expr> <C-e>     compe#close('<C-e>')
" inoremap <silent><expr> <Tab>     compe#confirm('<Tab>')
inoremap <silent><expr> <C-f>     compe#scroll({ 'delta': +4 })
inoremap <silent><expr> <C-d>     compe#scroll({ 'delta': -4 })
