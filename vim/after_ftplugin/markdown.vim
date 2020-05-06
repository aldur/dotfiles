setlocal spell spelllang=en,it
setlocal textwidth=80
setlocal conceallevel=0
setlocal nojoinspaces

let b:ale_linters = ['mdl', ]
let b:ale_fixers = ['prettier', ]
" This configures prettier for Markdown even if it says javascript :)
let b:ale_javascript_prettier_options = '--tab-width 4'

" Disable three backticks disappearing on new-line
let b:pear_tree_repeatable_expand = 0

function! s:HeaderDecrease() abort
    if match(getline('.'), '^# ') > -1
        execute 'silent! substitute/^# //'
        return
    endif

    execute '.HeaderDecrease'
endfunction

function! s:HeaderIncrease() abort
    if match(getline('.'), '^#') > -1
        execute '.HeaderIncrease'
        return
    endif

    execute 'silent! substitute/^/# /'
endfunction

nnoremap <silent><buffer> + :<c-U> call <SID>HeaderIncrease()<CR>
nnoremap <silent><buffer> - :<c-U> call <SID>HeaderDecrease()<CR>
