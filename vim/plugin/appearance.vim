set background=dark

let g:molokai_original = 0 " Prefer gray background color
let g:rehash256 = 1        " Enable experimental 256 colors support
silent! colorscheme molokai  " set the Molokai colorscheme, if it's installed

" Fix highlighting matching parenthesis and other smaller annoiances.
highlight MatchParen cterm=bold ctermfg=141 ctermbg=0 gui=bold guifg=#ae81ff guibg=0

" Bad words are orange.
highlight SpellBad guifg=orange

" Improve VimTeX syntax highlight.
highlight Special guibg=0

set fillchars=""  " Disable split separator characters

" Show snippet_complete marker (if any)
if has('conceal')
    set conceallevel=2 concealcursor=""
endif

" Line and relative numbers
set number
set relativenumber

" Only show cursorline in current window
" autocmd vimrc WinEnter * set cursorline
" autocmd vimrc WinLeave * set nocursorline

" White spaces
scriptencoding utf8
set list                                           " Display white spaces
set listchars=tab:→\ ,trail:•,                     " Custom characters highlights
set listchars+=extends:⟩,precedes:⟨,
set listchars+=\nbsp:␣,conceal:*,
let &showbreak = '↪'                               " Show whether lines have been wrapped

set showtabline=1  " Only show the tabline if there are at least two tab pages.

set noshowmode   " Do not show mode indicator below status bar
set laststatus=2 " Always show the statusbar

set termguicolors

if has('nvim')
    " Restore terminal cursor when nvim leaves.
    autocmd vimrc VimLeave * set guicursor=a:hor10-blinkon0
endif
