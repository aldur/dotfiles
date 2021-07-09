" set complete+=k
" set complete+=kspell
set complete=.,w,b,u

" This enables Dictionary completion in deoplete
" In standard VIM completion,this should not be required as it defaults to the
" spell files (if enabled), but `deoplete-dictionary` cannot parse those
" files, so we make it default to macOS words.
" Disabled, simply `setlocal` it in a buffer to enable completion.
" set dictionary+=/usr/share/dict/words

if has('patch-7.4.314')
    set shortmess+=c " Quiet completions
endif

lua require('plugins/nvim-lspconfig')

" Enable completion-nvim on all buffers.
" autocmd vimrc BufEnter * lua require'completion'.on_attach()

" Set completeopt to have a better completion experience
set completeopt=menuone,noinsert,noselect

let g:completion_enable_auto_popup = 1
let g:completion_enable_snippet = 'UltiSnips'
let g:completion_trigger_on_delete = 1
let g:completion_enable_auto_paren = 1
let g:completion_auto_change_source = 0

let g:completion_chain_complete_list = {
    \'default' : [
    \    {'complete_items': ['lsp', 'snippet']},
    \    {'mode': '<c-p>'},
    \    {'mode': '<c-n>'},
    \]
    \}

imap  <c-j> <Plug>(completion_next_source)
imap  <c-k> <Plug>(completion_prev_source)
