set showcmd               " Display incomplete commands

set magic                 " Magic pattern matching

set incsearch             " Find as you type search
set hlsearch              " Highlight search terms
set ignorecase            " Case insensitive search
set infercase             " Case sensitive completions
set smartcase             " Case sensitive when upper case is present
set gdefault              " Work on all matches on the line

if has('nvim')
    " Preview command results.
    set inccommand=nosplit
endif

set wildmenu              " Show list instead of just completing
set wildmode=longest,full " Command <Tab> completion, list matches, then longest common part, then all.

" Use sane magic regexes
nnoremap / /\v
vnoremap / /\v

nnoremap Q <Nop>

" When going back and forth in history, match prefixes
" Source: https://github.com/mhinz/vim-galore/issues/148
cnoremap <expr> <c-n> wildmenumode() ? "<c-n>" : "<down>"
cnoremap <expr> <c-p> wildmenumode() ? "<c-p>" : "<up>"

" Send the current filepath and line number to the clipboard (+ register).
command! FilepathToClipboard let @+ = expand('%') . ':' . line('.')
