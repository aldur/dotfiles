if isdirectory($HOME . '/.vim_backups/tags/') == 0
    call mkdir($HOME . '/.vim_backups/tags/', 'p')
endif
let g:gutentags_cache_dir = $HOME . '/.vim_backups/tags/'

" We take matter into our own hands
let g:gutentags_add_default_project_roots = 0

" This helps if the plugin isn't loaded.
let g:gutentags_project_root = get(g:, 'gutentags_project_root', [])

" We only use `git` as SVC
call add(g:gutentags_project_root, '.git')

" This makes sure that by dropping a `.enable_ctags` file in a directory, it
" will be indexed by gutentags.
call add(g:gutentags_project_root, '.enable_ctags')

" This ensures that when navigating to Python packages installed in a venv, we
" can quickly jump through dependencies (within and across projects). Kind of
" a HACK, but couldn't find a better way.
call add(g:gutentags_project_root, 'site-packages')

" Fix https://github.com/ludovicchabant/vim-gutentags/issues/178
let g:gutentags_exclude_filetypes = ['gitcommit', 'gitconfig', 'gitrebase', 'gitsendemail', 'git']

let g:gutentags_define_advanced_commands = 0
