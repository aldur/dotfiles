if !executable('ctags')
    finish
endif

if isdirectory($HOME . '/.vim/tags/') == 0
    call mkdir($HOME . '/.vim/tags/', 'p')
endif
let g:gutentags_cache_dir = $HOME . '/.vim/tags/'

" Only select .git folders as project roots.
let g:gutentags_add_default_project_roots = 0
let g:gutentags_project_root = [ '.git', ]
