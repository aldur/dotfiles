set complete+=k
set complete+=kspell
set completeopt=menuone,noinsert
set completeopt=menuone,longest

" This enables Dictionary completion in deoplete
" In standard VIM completion,this should not be required as it defaults to the
" spell files (if enabled), but `deoplete-dictionary` cannot parse those
" files, so we make it default to macOS words.
" Disabled, simply `setlocal` it in a buffer to enable completion.
" set dictionary+=/usr/share/dict/words

if has('patch-7.4.314')
    set shortmess+=c " Quiet completions
endif
