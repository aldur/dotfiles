"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Vundle requirements
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'

Plugin 'scrooloose/nerdtree'             " File explorer
Plugin 'scrooloose/syntastic'            " Syntax Checker (use it with pyflake8)
Plugin 'ervandew/supertab'               " Insert mode tab completion
Plugin 'SearchComplete'                  " Tab completion inside search
Plugin 'scrooloose/nerdcommenter'        " Useful commenter plugin
Plugin 'nathanaelkane/vim-indent-guides' " Indent guides
Plugin 'jmcantrell/vim-virtualenv'       " Virtualenv
Plugin 'bling/vim-airline'               " Better statusbar
Plugin 'nesC'                            " nesC syntax highlighting
Plugin 'kien/ctrlp.vim'                  " Fuzzy file, buffer, mru, tag finder
Plugin 'mileszs/ack.vim'                 " Ack plugin
Plugin 'tomasr/molokai'                  " Molokai colorscheme
Plugin 'fmoralesc/molokayo'              " Molokai improved
Plugin 'tpope/vim-fugitive'              " Git management inside VIM
Plugin 'tell-k/vim-autopep8'             " Automatic PEP8 - requires autopep8
Plugin 'luochen1990/rainbow'             " Rainbow parenthesis (no more messes!)
Plugin 'bogado/file-line'                " Open vim file:line
Plugin 'terryma/vim-multiple-cursors'    " Sublime Text like multiple cursors
Plugin 'godlygeek/tabular'               " Align text
Plugin 'auto-pairs-gentle'               " Auto pair parenthesis (gently)
Plugin 'majutsushi/tagbar'               " Show a cool tagbar (requires ctags)
Plugin 'django.vim'                      " Django syntax highlighting

if has('lua') && (v:version > 703 || (v:version == 703 && has('patch885')))
    " Use NeoComplete
    let g:neocomplete#enable_at_startup                 = 1
    let g:neocomplete#enable_smart_case                 = 1

    let g:neocomplete#data_directory                    = '~/.vim/neocomplcache'

    let g:neocomplete#sources#syntax#min_keyword_length = 3
    let g:neocomplete#lock_buffer_name_pattern          = '\*ku\*'

    " Define keyword.
    if !exists('g:neocomplete#keyword_patterns')
        let g:neocomplete#keyword_patterns              = {}
    endif
    let g:neocomplete#keyword_patterns['default']       = '\h\w*'
    let g:neocomplete#keyword_patterns._                = '\h\w*'
    let g:neocomplete#keyword_patterns.perl             = '\h\w*->\h\w*\|\h\w*::\w*'

    " Enable heavy omni completion.
    if !exists('g:neocomplete#sources#omni#input_patterns')
        let g:neocomplete#sources#omni#input_patterns = {}
    endif

    " let g:neocomplete#sources#omni#input_patterns     = {}
    " let g:neocomplete#sources#omni#input_patterns.php = '[^. \t]->\h\w*\|\h\w*::'
    " let g:neocomplete#sources#omni#input_patterns.c   = '[^.[:digit:] *\t]\%(\.\|->\)'
    " let g:neocomplete#sources#omni#input_patterns.cpp = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'

    " let g:neocomplete#force_omni_input_patterns       = {}
    " let g:neocomplete#force_omni_input_patterns.ruby  = '[^. *\t]\.\w*\|\h\w*::\w*'

    " let g:neocomplete#same_filetypes                  = {}
    " let g:neocomplete#same_filetypes.gitconfig        = '_'
    " let g:neocomplete#same_filetypes._                = '_'

    " Plugin key-mappings.
    inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
    function! s:my_cr_function()
        return pumvisible() ? neocomplete#close_popup() : "\<CR>"
    endfunction    
    " <TAB>: completion.
    inoremap <expr><TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"

    " <C-h>, <BS>: close popup and delete backword char.
    inoremap <expr><C-h> neocomplete#smart_close_popup()."\<C-h>"
    inoremap <expr><BS>  neocomplete#smart_close_popup()."\<C-h>"
    inoremap <expr><C-y> neocomplete#close_popup()
    inoremap <expr><C-e> neocomplete#cancel_popup()

    " Close popup by <Space>.
    inoremap <expr><Space> pumvisible() ? neocomplete#close_popup() : "\<Space>"

    inoremap <expr><C-g>     neocomplete#undo_completion()
    inoremap <expr><C-l>     neocomplete#complete_common_string()

    Plugin 'Shougo/neocomplete'

elseif v:version > 702
    " Use NeoComplCache
    let g:neocomplcache_enable_at_startup             = 1
    let g:neocomplcache_force_overwrite_completefunc  = 1

    " Store temporary files in standard location.
    let g:neocomplcache_temporary_dir                 = '~/.vim/neocomplcache'

    " Define keyword.
    let g:neocomplcache_keyword_patterns              = {}
    let g:neocomplcache_keyword_patterns['default']   = '\h\w*'

    " Enable heavy omni completion.
    let g:neocomplcache_omni_patterns                 = {}
    "let g:neocomplcache_omni_patterns.ruby           = '[^. *\t]\.\w*\|\h\w*::'
    let g:neocomplcache_omni_patterns.php             = '[^. \t]->\h\w*\|\h\w*::'
    let g:neocomplcache_omni_patterns.c               = '[^.[:digit:] *\t]\%(\.\|->\)'
    let g:neocomplcache_omni_patterns.cpp             = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'

    " For perlomni.vim setting.
    " https://github.com/c9s/perlomni.vim
    "let g:neocomplcache_omni_patterns.perl           = '\h\w*->\h\w*\|\h\w*::'

    if !exists('g:neocomplcache_force_omni_patterns')
        let g:neocomplcache_force_omni_patterns       = {}
    endif
    let g:neocomplcache_force_omni_patterns.ruby      = '[^. *\t]\.\w*\|\h\w*::'

    " Completes from all buffers.
    if !exists('g:neocomplcache_same_filetype_lists')
        let g:neocomplcache_same_filetype_lists = {}
    endif
    let g:neocomplcache_same_filetype_lists.gitconfig = '_'
    let g:neocomplcache_same_filetype_lists._ = '_'

    " Disable NeoComplCache for certain filetypes
    if has('autocmd')
        augroup NeoComplCache
            autocmd!
            autocmd FileType pandoc,markdown nested NeoComplCacheLock
        augroup END
    endif

    Plugin 'Shougo/neocomplcache'

    inoremap <expr> <C-g> neocomplcache#undo_completion()
    inoremap <expr> <C-l> neocomplcache#complete_common_string()
    inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
    function! s:my_cr_function()
        return neocomplcache#smart_close_popup() . "\<CR>"
    endfunction
    inoremap <expr> <TAB>  pumvisible() ? "\<C-n>" : "\<TAB>"
    inoremap <expr> <C-h> neocomplcache#smart_close_popup()."\<C-h>"
    inoremap <expr> <BS> neocomplcache#smart_close_popup()."\<C-h>"
    inoremap <expr> <C-y>  neocomplcache#close_popup()
    inoremap <expr> <C-e>  neocomplcache#cancel_popup()

endif

" Use NeoSnippet
Plugin 'honza/vim-snippets'

" Tell NeoSnippet about these snippets
let g:neosnippet#snippets_directory='~/.vim/bundle/vim-snippets/snippets'
Plugin 'Shougo/neosnippet'

" And disable the default ones
" Plugin 'Shougo/neosnippet-snippets'
let g:neosnippet#disable_runtime_snippets = {
    \ '_' : 1,
\ }

" Plugin key-mappings.
imap <C-k>     <Plug>(neosnippet_expand_or_jump)
smap <C-k>     <Plug>(neosnippet_expand_or_jump)
xmap <C-k>     <Plug>(neosnippet_expand_target)

" SuperTab like snippets behavior.
" imap <expr><TAB> neosnippet#expandable_or_jumpable() ?
"             \ "\<Plug>(neosnippet_expand_or_jump)"
"             \: pumvisible() ? "\<C-n>" : "\<TAB>"
" smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
"             \ "\<Plug>(neosnippet_expand_or_jump)"
"             \: "\<TAB>"

" For snippet_complete marker.
if has('conceal')
    set conceallevel=2 concealcursor=i
endif

" All your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => General
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Sets how many lines of history VIM has to remember
set history=500

" Set to auto read when a file is changed from the outside
set autoread

" With a map leader it's possible to do extra key combinations
" like <leader>w saves the current file
let mapleader   = ","
let g:mapleader = ","

" Fast saving
nmap <leader>w :w!<cr>

" Better ESC key 
inoremap jk <ESC>

" Mouse
set mouse=a

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => VIM user interface
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Save your backups to a less annoying place than the current directory.
" If you have .vim-backup in the current directory, it'll use that.
" Otherwise it saves it to ~/.vim/backup or . if all else fails.
if isdirectory($HOME . '/.vim/backup') == 0
    :silent !mkdir -p ~/.vim/backup >/dev/null 2>&1
endif
set backupdir-=.
set backupdir+=.
set backupdir-=~/
set backupdir^=~/.vim/backup/
set backupdir^=./.vim-backup/
set backup

" Save your swp files to a less annoying place than the current directory.
" If you have .vim-swap in the current directory, it'll use that.
" Otherwise it saves it to ~/.vim/swap, ~/tmp or .
if isdirectory($HOME . '/.vim/swap') == 0
    :silent !mkdir -p ~/.vim/swap >/dev/null 2>&1
endif
set directory=./.vim-swap//
set directory+=~/.vim/swap//
set directory+=~/tmp//
set directory+=.

" viminfo stores the the state of your previous editing session
set viminfo+=n~/.vim/viminfo

if exists("+undofile")
    " undofile - This allows you to use undos after exiting and restarting
    " This, like swap and backups, uses .vim-undo first, then ~/.vim/undo
    " :help undo-persistence
    " This is only present in 7.3+
    if isdirectory($HOME . '/.vim/undo') == 0
        :silent !mkdir -p ~/.vim/undo > /dev/null 2>&1
    endif
    set undodir=./.vim-undo//
    set undodir+=~/.vim/undo//
    set undofile
endif

" Set 7 lines to the cursor - when moving vertically using j/k
set so=7

" Turn on the WiLd menu
set wildmenu

set wildmode=longest,full   " Completion for wildchar (see help)

" Ignore compiled files and images
set wildignore=*.o,*~,*.pyc
set wildignore+=*.png,*.gif,*.jpg,*.ico
set wildignore+=.git,.svn,.hg

set completeopt=menu,longest
set omnifunc=syntaxcomplete#Complete " This is overriden by syntax plugins.

if has('autocmd')
    augroup OmniCompleteModes
        autocmd!
        autocmd FileType python        nested setlocal omnifunc=pythoncomplete#Complete
        autocmd FileType ruby,eruby    nested setlocal omnifunc=rubycomplete#Complete
        autocmd FileType css           nested setlocal omnifunc=csscomplete#CompleteCSS
        autocmd FileType html,markdown nested setlocal omnifunc=htmlcomplete#CompleteTags
        autocmd FileType javascript    nested setlocal omnifunc=javascriptcomplete#CompleteJS
        autocmd FileType xml           nested setlocal omnifunc=xmlcomplete#CompleteTags
    augroup END
endif

" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright

"Always show current position
set cursorline                   " highlights the current line
set ruler

" Height of the command bar
set cmdheight=2

" A buffer becomes hidden when it is abandoned
set hid

" Configure backspace so it acts as it should act
set backspace=eol,start,indent
set whichwrap+=<,>,h,l

" Ignore case when searching
set ignorecase

" When searching try to be smart about cases 
set smartcase

" Highlight search results
set hlsearch

" Makes search act like search in modern browsers
set incsearch

" Don't redraw while executing macros (good performance config)
set lazyredraw

" For regular expressions turn magic on
set magic

" Show matching brackets when text indicator is over them
set showmatch
" How many tenths of a second to blink when matching brackets
set mat=2

" No annoying sound on errors
set noerrorbells visualbell t_vb=
if has('autocmd')
  autocmd GUIEnter * set visualbell t_vb=
endif

set tm=500

" Line numbers
set number
set relativenumber

set showcmd		" display incomplete commands

" Timeout after insert mode to command mode
set ttimeoutlen=50

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Colors and Fonts
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Enable syntax highlighting
syntax enable

set background=dark
colorscheme molokai

set scrolloff=5       " don't scroll any closer to top/bottom
set sidescrolloff=5   " don't scroll any closer to left/right

" Set extra options when running in GUI mode
if has("gui_running")
    set guioptions-=T
    set guioptions+=e
    set t_Co=256
    set guitablabel=%M\ %t
endif

" Set utf8 as standard encoding and en_US as the standard language
set encoding=utf8

" Use Unix as the standard file type
set ffs=unix,dos,mac


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Text, tab and indent related
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Use spaces instead of tabs
set expandtab

" Be smart when using tabs ;)
set smarttab

set shiftwidth=4  " operation >> indents 4 columns; << unindents 4 columns
set tabstop=4     " a hard TAB displays as 4 columns
set expandtab     " insert spaces when hitting TABs
set softtabstop=4 " insert/delete 4 spaces when hitting a TAB/BACKSPACE
set shiftround    " round indent to multiple of 'shiftwidth'
set autoindent    " align the new line indent with the previous line

set si            " Smart indent
set wrap          " Wrap lines

" Linebreak on 500 characters
set lbr
set tw=500

set formatoptions=c,q,r,t 

" Indent whole file
nmap <silent> <Leader>g :call Preserve("normal gg=G")<CR>

"""""""""""""""""""""""""""""
" => Visual mode related
""""""""""""""""""""""""""""""
" Visual mode pressing * or # searches for the current selection
" Super useful! From an idea by Michael Naumann
vnoremap <silent> * :call VisualSelection('f')<CR>
vnoremap <silent> # :call VisualSelection('b')<CR>

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Moving around, tabs, windows and buffers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Treat long lines as break lines (useful when moving around in them)
map j gj
map k gk

" Map <Space> to / (search) and Ctrl-<Space> to ? (backwards search)
" map <space> /
" map <c-space> ?

" Disable highlight when <leader><cr> is pressed
map <silent> <leader><cr> :noh<cr>

" Smart way to move between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" Close the current buffer
map <leader>bd :Bclose<cr>

" Close all the buffers
map <leader>ba :1,1000 bd!<cr>

" Useful mappings for managing tabs
map <leader>tn :tabnew<cr>
map <leader>to :tabonly<cr>
map <leader>tc :tabclose<cr>
map <leader>tm :tabmove

" Opens a new tab with the current buffer's path
" Super useful when editing files in the same directory
map <leader>te :tabedit <c-r>=expand("%:p:h")<cr>/

" Switch CWD to the directory of the open buffer
map <leader>cd :cd %:p:h<cr>:pwd<cr>

" Specify the behavior when switching between buffers 
try
    set switchbuf=useopen,usetab,newtab
    set stal=2
catch
endtry

" Return to last edit position when opening files (You want this!)
autocmd BufReadPost *
            \ if line("'\"") > 0 && line("'\"") <= line("$") |
            \   exe "normal! g`\"" |
            \ endif
" Remember info about open buffers on close
set viminfo^=%


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Editing mappings
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Remap VIM 0 to first non-blank character
"
map 0 ^

" Move a line of text using ALT+[jk] or Comamnd+[jk] on mac
nmap <M-j> mz:m+<cr>`z
nmap <M-k> mz:m-2<cr>`z
vmap <M-j> :m'>+<cr>`<my`>mzgv`yo`z
vmap <M-k> :m'<-2<cr>`>my`<mzgv`yo`z

if has("mac") || has("macunix")
    nmap <D-j> <M-j>
    nmap <D-k> <M-k>
    vmap <D-j> <M-j>
    vmap <D-k> <M-k>
endif

" Delete trailing white space on save, useful for Python and CoffeeScript ;)
func! DeleteTrailingWS()
    exe "normal mz"
    %s/\s\+$//ge
    exe "normal `z"
endfunc
autocmd BufWrite *.py :call DeleteTrailingWS()
autocmd BufWrite *.coffee :call DeleteTrailingWS()

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Spell checking
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Pressing ,ss will toggle and untoggle spell checking
map <leader>ss :setlocal spell!<cr>
" Quickly enable spell checking (alternate method)
map <F6> :setlocal spell! spelllang=en_us<CR>

" Shortcuts using <leader>
map <leader>sn ]s
map <leader>sp [s
map <leader>sa zg
map <leader>s? z=

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Misc
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Remove the Windows ^M - when the encodings gets messed up
noremap <Leader>m mmHmt:%s/<C-V><cr>//ge<cr>'tzt'm

" Toggle paste mode on and off
map <leader>pp :setlocal paste!<cr>

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" => Helper functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! CmdLine(str)
    exe "menu Foo.Bar :" . a:str
    emenu Foo.Bar
    unmenu Foo
endfunction

function! VisualSelection(direction) range
    let l:saved_reg = @"
    execute "normal! vgvy"

    let l:pattern = escape(@", '\\/.*$^~[]')
    let l:pattern = substitute(l:pattern, "\n$", "", "")

    if a:direction == 'b'
        execute "normal ?" . l:pattern . "^M"
    elseif a:direction == 'gv'
        call CmdLine("vimgrep " . '/'. l:pattern . '/' . ' **/*.')
    elseif a:direction == 'replace'
        call CmdLine("%s" . '/'. l:pattern . '/')
    elseif a:direction == 'f'
        execute "normal /" . l:pattern . "^M"
    endif

    let @/ = l:pattern
    let @" = l:saved_reg
endfunction

" A wrapper function to restore the cursor position, window position,
" and last search after running a command.
function! Preserve(command)
    " Save the last search
    let last_search=@/
    " Save the current cursor position
    let save_cursor = getpos('.')
    " Save the window position
    normal H
    let save_window = getpos('.')
    call setpos('.', save_cursor)

    " Do the business:
    execute a:command

    " Restore the last_search
    let @/=last_search
    " Restore the window position
    call setpos('.', save_window)
    normal zt
    " Restore the cursor position
    call setpos('.', save_cursor)
endfunction

" Returns true if paste mode is enabled
function! HasPaste()
    if &paste
        return 'PASTE MODE  '
    en
    return ''
endfunction

" Don't close window, when deleting a buffer
command! Bclose call <SID>BufcloseCloseIt()
function! <SID>BufcloseCloseIt()
    let l:currentBufNum = bufnr("%")
    let l:alternateBufNum = bufnr("#")

    if buflisted(l:alternateBufNum)
        buffer #
    else
        bnext
    endif

    if bufnr("%") == l:currentBufNum
        new
    endif

    if buflisted(l:currentBufNum)
        execute("bdelete! ".l:currentBufNum)
    endif
endfunction

" Convenient command to see the difference between the current buffer and the
" file it was loaded from, thus the changes you made.
" Only define it when not defined already.
if !exists(':DiffOrig')
    command DiffOrig vert new | set bt=nofile | r ++edit # | 0d_ | diffthis
                \ | wincmd p | diffthis
endif

" Misc. Commands
"-----------------------------------------------------------------------------
" Disable autocommenting
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o

" Tagbar
nnoremap <silent> <leader>tb :TagbarToggle<CR>

" NerdCommenter settings
let NERDSpaceDelims=1           " place spaces after comment chars
let g:NERDRemoveExtraSpaces=1
let g:NERDCommentWholeLinesInVMode=2

" NerdTree settings
nnoremap <silent> <leader>kb :call NERDTreeFindOrClose()<CR>
function! NERDTreeFindOrClose()
    if exists('t:NERDTreeBufName') && bufwinnr(t:NERDTreeBufName) != -1
        NERDTreeClose
    else
        if bufname('%') == ''
            NERDTree
        else
            NERDTreeFind
        endif
    endif
endfunction
let NERDTreeBookmarksFile = expand('~/.vim/NERDTreeBookmarks')
let NERDTreeShowBookmarks=1
let NERDTreeQuitOnOpen=1
let NERDTreeMouseMode=2
let NERDTreeShowHidden=1
let g:nerdtree_tabs_open_on_gui_startup=0
let NERDTreeIgnore=['\.o$', '\.so$', '\.bmp$', '\.class$', '^core.*',
            \ '\.vim$', '\~$', '\.pyc$', '\.pyo$', '\.jpg$', '\.gif$',
            \ '\.png$', '\.ico$', '\.exe$', '\.cod$', '\.obj$', '\.mac$',
            \ '\.1st', '\.dll$', '\.pyd$', '\.zip$', '\.modules$',
            \ '\.git', '\.hg', '\.svn', '\.bzr' ]

" NesC syntax load
augroup filetypedetect
    au! BufRead,BufNewFile *nc setfiletype nc
augroup END

" ctrlp settings
" first of all, the mappings
let g:ctrlp_map = '<c-p>' 
let g:ctrlp_cmd = 'CtrlP'
" set the local working directory
let g:ctrlp_working_path_mode = 'ra'
set wildignore+=*/tmp/*,*.so,*.swp,*.zip     " MacOSX/Linux

let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'

" Vim Airline configuration
let g:airline#extensions#tabline#enabled = 1 "  smarter tab view
let g:airline_powerline_fonts = 1            "  powerline fonts
let g:airline_theme = "dark"                 "  dark theme
" let g:airline#extensions#whitespace#enabled = 0

" Autopep8 settings
let g:autopep8_disable_show_diff=1 " Do not show diff after autopep8 

" Statusbar goodies
let g:bufferline_echo = 0
set noshowmode   " show statusbar by default
set laststatus=2 " always show the statusbar

if has("autocmd")
    " Highlight TODO, FIXME, NOTE, etc.
    if v:version > 701
        autocmd Syntax * call matchadd('Todo',  '\W\zs\(TODO\|FIXME\|CHANGED\|XXX\|BUG\|HACK\)')
        autocmd Syntax * call matchadd('Debug', '\W\zs\(NOTE\|INFO\|IDEA\)')
    endif
endif

" Syntastic settings
let g:syntastic_check_on_open        = 1
let g:syntastic_error_symbol         = "✗"  " Better error and warning icons
let g:syntastic_warning_symbol       = "⚠"
let g:syntastic_style_error_symbol   = '⚡'
let g:syntastic_style_warning_symbol = '⚡'

" Rainbow parenthesis settings
let g:rainbow_active = 1  " Activate rainbows

" Auto-pairs-gentle settings
let g:AutoPairsUseInsertedCount = 1  " Make it gentle

" Vim multiple cursors settings
let g:multi_cursor_exit_from_visual_mode = 1  " Keep cursors when exiting from V mode
" let g:multi_cursor_exit_from_insert_mode = 1  " Keep cursors when exiting from I mode

if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif

set secure

" Habits breaking!
noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>
