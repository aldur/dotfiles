set showcmd               " Display incomplete commands

" Magic pattern matching
set magic

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
