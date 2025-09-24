scriptencoding utf8

" This is set by the colorscheme, but if it's not installed
" it's still nice to have a black background.
set background=dark

if has('termguicolors')
    set termguicolors
endif

autocmd vimrc ColorScheme sonokai call aldur#colors#customize_sonokai()

" The configuration options should be placed before `colorscheme sonokai`.
let g:sonokai_style = 'atlantis'
let g:sonokai_enable_italic = 1
let g:sonokai_better_performance = 1
let g:sonokai_show_eob = 0
let g:sonokai_diagnostic_virtual_text = 1

silent! colorscheme sonokai

set fillchars=""  " Disable split separator characters

" Show snippet_complete marker (if any)
if has('conceal')
    set conceallevel=2 concealcursor=""
endif

" Line and relative numbers
set number
set relativenumber

" Only show cursorline in current window
" -- Disabled as, in general, it slows down redrawing
" autocmd vimrc WinEnter * set cursorline
" autocmd vimrc WinLeave * set nocursorline

" Only show line number on the current window
" -- Disabled as it makes the alignment of text jump back and forth.
" autocmd vimrc WinEnter * set number relativenumber
" autocmd vimrc WinLeave * set nonumber norelativenumber

" Disable signcolumn
" -- Note that you need `BufRead`/`BufNewFile` because `WintEnter`
" -- does not apply to the first window.
" autocmd vimrc BufRead,BufNewFile * setlocal signcolumn=no

" White spaces
set list                                           " Display white spaces
set listchars=tab:→\ ,trail:•,                     " Custom characters highlights
set listchars+=extends:⟩,precedes:⟨,
set listchars+=\nbsp:␣,conceal:*,
let &showbreak = '↪'                               " Show whether lines have been wrapped

set showtabline=1  " Only show the tabline if there are at least two tab pages.

set noshowmode   " Do not show mode indicator below status bar

call aldur#appearance#setlaststatus()

" Restore terminal cursor when nvim leaves.
autocmd vimrc VimLeave * set guicursor=a:hor10-blinkon0

set scrolloff=8       " don't scroll any closer to top/bottom
set sidescrolloff=5   " don't scroll any closer to left/right

" No annoying sound on errors
set noerrorbells novisualbell

" Allow the cursor to be one more the last char.
set virtualedit=onemore

" Do not resize when opening or closing windows
set noequalalways

" Set minimum height and width for windows
" set winminheight=10 winminwidth=10

autocmd vimrc TextYankPost * silent! lua vim.hl.on_yank()
