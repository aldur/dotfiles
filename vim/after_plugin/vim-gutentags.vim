if isdirectory($HOME . '/.vim_backups/tags/') == 0
    call mkdir($HOME . '/.vim_backups/tags/', 'p')
endif
let g:gutentags_cache_dir = $HOME . '/.vim_backups/tags/'

" Only select .git folders as project roots.
let g:gutentags_add_default_project_roots = 0

" This makes sure that by dropping a `.enable_ctags` file in a directory, it
" will be indexed by gutentags.
let g:gutentags_project_root = [ '.git', '.enable_ctags']

" Fix https://github.com/ludovicchabant/vim-gutentags/issues/178
let g:gutentags_exclude_filetypes = ['gitcommit', 'gitconfig', 'gitrebase', 'gitsendemail', 'git']

let g:gutentags_define_advanced_commands = 0
