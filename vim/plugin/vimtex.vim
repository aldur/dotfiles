" if !exists(':LatexCompile')
"     finish
" endif

let g:tex_flavor = 'latex'  " Open '.tex' files as 'tex' and not 'plaintex'.
let g:vimtex_quickfix_mode = 2  " Auto-open quickfix with no focus.

if has('nvim')
    if filereadable('/usr/local/bin/nvr')
        let g:vimtex_compiler_progname = '/usr/local/bin/nvr'
    elseif filereadable('/opt/homebrew/bin/nvr')
        let g:vimtex_compiler_progname = '/opt/homebrew/bin/nvr'
    endif
end

if has('mac')
    let g:vimtex_view_method = 'skim'
end

let g:vimtex_imaps_enabled = 0   " Disable insert mode mappings
let g:vimtex_fold_enabled = 0    " Enable vimtex folds
let g:vimtex_format_enabled = 1  " Enable better formatting with gq

" Disable overfull/underfull \hbox
let g:vimtex_quickfix_ignore_filters = [
    \ 'overfull',
    \ 'underfull',
    \]
