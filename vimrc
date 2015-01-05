" Modeline and Notes {
" vim: set sw=4 ts=4 sts=4 et tw=78 foldmarker={,} foldlevel=0 foldmethod=marker spell:
" }

" Vundle {
    set nocompatible              " be VIMproved, required
    filetype off

    " set the runtime path to include Vundle and initialize
    set rtp+=~/.vim/bundle/Vundle.vim
    call vundle#begin()

    " let Vundle manage Vundle
    Plugin 'gmarik/Vundle.vim'

    " the list of installed plugins
    Plugin 'mattn/webapi-vim'                " Gist require it
    Plugin 'scrooloose/nerdtree'             " File explorer
    Plugin 'scrooloose/syntastic'            " Syntax Checker (install pyflake to enable python checking)
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
    Plugin 'tpope/vim-surround'              " All about surrounding
    Plugin 'honza/vim-snippets'              " Vim snippets
    Plugin 'jtratner/vim-flavored-markdown'  " GitHub flavored markdown
    " Plugin 'suan/vim-instant-markdown'       " Instant markdown preview in browser (requirements on GH)
    Plugin 'mattn/gist-vim'                  " Gists!
    Plugin 'tmhedberg/SimpylFold'            " Python correct folding

    if has('lua')
        Plugin 'Shougo/neocomplete.vim'      " Vim completion
        Plugin 'Shougo/neosnippet.vim'       " And snippets engine
    endif

    " ...Vundle is done
    call vundle#end()
    filetype plugin indent on
" }

" General {
    " Sets how many lines of history VIM has to remember
    set history=1000

    " Set to auto read when a file is changed from the outside
    set autoread

    " Mouse
    set mouse=a
    set mousehide               " Hide the mouse cursor while typing

    " With a map leader it's possible to do extra key combinations
    let mapleader   = ","
    let g:mapleader = ","

    " Timeout after insert mode to command mode
    set ttimeoutlen=50
" }

" Backup, swap, unfo and ignore files {
    set noswapfile  " Stop annoying swap files

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

    " Ignore unreadable files, images, etc.
    set wildignore=*.o,*~,*.pyc
    set wildignore+=*.png,*.gif,*.jpg,*.ico
    set wildignore+=.git,.svn,.hg
    set wildignore+=*/tmp/*,*.so,*.swp,*.zip
" }

" Appeareance {
    syntax enable

    "Always show current position
    set cursorline                   " highlights the current line

    " Height of the command bar
    set cmdheight=2

    set background=dark
    colorscheme molokai

    set scrolloff=8       " don't scroll any closer to top/bottom
    set sidescrolloff=5   " don't scroll any closer to left/right

    " No annoying sound on errors
    set noerrorbells visualbell t_vb=
    if has('autocmd')
        autocmd GUIEnter * set visualbell t_vb=
    endif

    " Line and relative numbers
    set number
    set relativenumber

    set showmatch                   " Show matching brackets/parenthesis
    set matchtime=2                 " How many tenths of seconds to blink matching bracket/parenthesis

    set linespace=0                 " No extra spaces between rows

    " How to show completion informations in insert mode
    set completeopt=menu,longest
" }

" Search and commands {
    set showcmd               " display incomplete commands

    set incsearch             " Find as you type search
    set hlsearch              " Highlight search terms
    set ignorecase            " Case insensitive search
    set smartcase             " Case sensitive when upper case is present
    set wildmenu              " Show list instead of just completing
    set wildmode=longest,full " Command <Tab> completion, list matches, then longest common part, then all.

    " Magic pattern matching
    set magic
" }

" Text, lines, tab, indent and folding {
    " Set utf8 as standard encoding
    set encoding=utf-8  " The encoding displayed.
    set fileencoding=utf-8  " The encoding written to file.

    set backspace=indent,eol,start  " Backspace for dummies
    set winminheight=0              " Windows can be 0 line high
    set whichwrap=b,s,h,l,<,>,[,]   " Backspace and cursor keys wrap too
    set list                        " Display whites
    set listchars=tab:›\ ,trail:•,extends:#,nbsp:. " Highlight problematic whitespace

    set expandtab     " In insert mode, insert the appropriate number of spaces to insert a Tab
    set smarttab      " Insert tabs in front of lines according to shiftwidth
    set shiftwidth=4  " operation >> indents 4 columns; << unindents 4 columns
    set tabstop=4     " a hard TAB displays as 4 columns
    set expandtab     " insert spaces when hitting TABs
    set softtabstop=4 " insert/delete 4 spaces when hitting a TAB/BACKSPACE
    set shiftround    " round indent to multiple of 'shiftwidth'
    set autoindent    " align the new line indent with the previous line
    set cindent       " automatic C programming indenting

    " Visually wrap lines too long
    set wrap
    " turns off physical line wrapping
    set textwidth=0 wrapmargin=0

    set foldenable                  " Auto fold code
    set foldmethod=syntax

    " Save fold state when leaving / restore when entering buffer
    " Remember to create ~/.vim/view
    autocmd BufEnter .* mkview
    autocmd BufLeave .* silent loadview
" }

" Tabs, windows and buffers {
    set hidden  " Allow to change buffer without saving

    " Open new split panes to right and bottom, which feels more natural
    set splitbelow
    set splitright

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
        set showtabline=2
    catch
    endtry

    set viminfo^=%
" }

" Misc mappings {
    " Fast saving
    nmap <leader>w :w!<cr>

    " Remap VIM 0 to first non-blank character
    map 0 ^

    " Treat long lines as break lines (useful when moving around in them)
    map j gj
    map k gk

    " Disable highlight when <leader><cr> is pressed
    map <silent> <leader><cr> :noh<cr>

    " Toggle paste mode on and off
    map <leader>pp :setlocal paste!<cr>

    " Indent whole file
    nmap <silent> <Leader>g :call Preserve("normal gg=G")<CR>

    " Visual shifting (does not exit Visual mode)
    vnoremap < <gv
    vnoremap > >gv
" }

" Spell checking {
    " Pressing ,ss will toggle and untoggle spell checking
    map <leader>ss :setlocal spell!<cr>

    " Shortcuts using <leader>
    map <leader>sn ]s
    map <leader>sp [s
    map <leader>sa zg
    map <leader>s? z=
" }

" Misc {
    if has("autocmd")
        " Highlight TODO, FIXME, NOTE, etc.
        autocmd Syntax * call matchadd('Todo',  '\W\zs\(TODO\|FIXME\|CHANGED\|XXX\|BUG\|HACK\)')
        autocmd Syntax * call matchadd('Debug', '\W\zs\(NOTE\|INFO\|IDEA\)')
    endif

    " Let's brake some habits...
    noremap <Up> <NOP>
    noremap <Down> <NOP>
    noremap <Left> <NOP>
    noremap <Right> <NOP>
" }

" Helper functions {
    " Most prefer to automatically switch to the current file directory when
    " a new buffer is opened
    autocmd BufEnter * if bufname("") !~ "^\[A-Za-z0-9\]*://" && bufname("") !~"^gist" | lcd %:p:h | endif

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

    " Convenient command to see the difference between the current buffer and the
    " file it was loaded from, thus the changes you made.
    " Only define it when not defined already.
    if !exists(':DiffOrig')
        command DiffOrig vert new | set bt=nofile | r ++edit # | 0d_ | diffthis
                    \ | wincmd p | diffthis
    endif

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

    " Strip whitespace {
    function! StripTrailingWhitespace()
        " Preparation: save last search, and cursor position.
        let _s=@/
        let l = line(".")
        let c = col(".")
        " do the business:
        %s/\s\+$//e
        " clean up: restore previous search history, and cursor position
        let @/=_s
        call cursor(l, c)
    endfunction
    " }

    " Before saving, delete trailing withspaces and ^M
    autocmd FileType c,cpp,java,go,php,javascript,python,twig,xml,yml,vim autocmd BufWritePre <buffer> call StripTrailingWhitespace()

    " http://vim.wikia.com/wiki/Restore_cursor_to_file_position_in_previous_editing_session
    " Restore cursor to file position in previous editing session
    function! ResCur()
        if line("'\"") <= line("$")
            normal! g`"
            return 1
        endif
    endfunction

    augroup resCur
        autocmd!
        autocmd BufWinEnter * call ResCur()
    augroup END

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
" }

" Plugin settings {
    " Tagbar {
        nnoremap <silent> <leader>tb :TagbarToggle<CR>
    " }

    " NerdCommenter {
        let NERDSpaceDelims=1
        let g:NERDRemoveExtraSpaces=1
        let g:NERDCommentWholeLinesInVMode=2
    " }

    " NerdTree {
        nnoremap <silent> <leader>kb :call NERDTreeFindOrClose()<CR>
        let NERDTreeShowBookmarks=1
        let NERDTreeQuitOnOpen=1
        let NERDTreeMouseMode=2
        let g:nerdtree_tabs_open_on_gui_startup=0
        let g:nerdtree_tabs_open_on_console_startup=0
        let NERDTreeShowHidden=0
        let g:NERDTreeMapOpenInTabSilent = 't'
        let g:NERDTreeMapOpenInTabSilent = 'f'
        let NERDTreeAutoDeleteBuffer=1
        let NERDTreeChDirMode=2
        let NERDTreeIgnore=['\.o$', '\.so$', '\.bmp$', '\.class$', '^core.*',
                    \ '\.vim$', '\~$', '\.pyc$', '\.pyo$', '\.jpg$', '\.gif$',
                    \ '\.png$', '\.ico$', '\.exe$', '\.cod$', '\.obj$', '\.mac$',
                    \ '\.1st', '\.dll$', '\.pyd$', '\.zip$', '\.modules$',
                    \ '\.git', '\.hg', '\.svn', '\.bzr' ]
    " }

    " nesC {
        augroup filetypedetect
            au! BufRead,BufNewFile *nc setfiletype nc
        augroup END
    " }

    " CtrlP {
        let g:ctrlp_map = '<c-p>'
        let g:ctrlp_cmd = 'CtrlP'
        let g:ctrlp_working_path_mode = 'ra'

        let g:ctrlp_custom_ignore = {
        \ 'dir':  '\.git$\|\.yardoc\|public$|log\|tmp$|backup',
        \ 'file': '\.so$\|\.dat$|\.DS_Store$'
        \ }

        let g:ctrlp_cache_dir = $HOME.'/.vim/.cache/ctrlp'
        let g:ctrlp_match_window_reversed = 1
        let g:ctrlp_clear_cache_on_exit=0
    " }

    " Autopep8 {
        let g:autopep8_disable_show_diff=1 " Do not show diff after autopep8
    " }

    " Vim Airline / Statusbar {
        let g:bufferline_echo = 0
        set noshowmode   " show statusbar by default
        set laststatus=2 " always show the statusbar

        let g:airline#extensions#tabline#enabled = 1 "  smarter tab view
        let g:airline_powerline_fonts = 1            "  powerline fonts
        let g:airline_theme = "dark"                 "  dark theme
        let g:airline#extensions#whitespace#enabled = 0
    " }

    " Syntastic {
        let g:syntastic_check_on_open        = 1
        let g:syntastic_error_symbol         = "✗"
        let g:syntastic_warning_symbol       = "⚠"
        let g:syntastic_style_error_symbol   = '⚡'
        let g:syntastic_style_warning_symbol = '⚡'
    " }

    " Rainbow parenthesis {
        let g:rainbow_active = 1  " Activate rainbows
    " }

    " Auto-pairs-gentle {
        let g:AutoPairsUseInsertedCount = 1  " Make it gentle
    " }

    " Multi Cursors {
        let g:multi_cursor_exit_from_visual_mode = 1  " Keep cursors when exiting from V mode
        " let g:multi_cursor_exit_from_insert_mode = 1  " Keep cursors when exiting from I mode
    " }

    " Neocomplete {
    if has('lua')
        let g:neocomplete#enable_at_startup                    = 1
        let g:neocomplete#enable_fuzzy_completion              = 1
        let g:neocomplete_enable_fuzzy_completion_start_length = 2
        let g:neocomplete_enable_camel_case_completion         = 0
        let g:neocomplete#enable_smart_case                    = 1
        let g:neocomplete#enable_auto_delimiter                = 1
        let g:neocomplete#max_list                             = 10
        let g:neocomplete#force_overwrite_completefunc         = 1
        let g:neocomplete#enable_auto_select                   = 0

        " Define keyword.
        let g:neocomplete#keyword_patterns                     = {}
        let g:neocomplete#keyword_patterns._                   = '\h\w*'

        " Plugin Keymaps {
            " <C-k> Complete Snippet
            " <C-k> Jump to next snippet point
            imap <silent><expr><C-k> neosnippet#expandable() ?
                        \ "\<Plug>(neosnippet_expand_or_jump)" : (pumvisible() ?
                        \ "\<C-e>" : "\<Plug>(neosnippet_expand_or_jump)")
            smap <TAB> <Right><Plug>(neosnippet_jump_or_expand)

            inoremap <expr><C-g> neocomplete#undo_completion()
            inoremap <expr><C-l> neocomplete#complete_common_string()
            " inoremap <expr><CR> neocomplete#complete_common_string()

            " <CR>: close popup
            " <s-CR>: close popup and save indent.
            inoremap <expr><s-CR> pumvisible() ? neocomplete#close_popup()"\<CR>" : "\<CR>"
            " inoremap <expr><CR> pumvisible() ? neocomplete#close_popup() : "\<CR>"

            function! CleverCr()
                if pumvisible()
                    if neosnippet#expandable()
                        let exp = "\<Plug>(neosnippet_expand)"
                        return exp . neocomplete#close_popup()
                    else
                        return neocomplete#close_popup()
                    endif
                else
                    return "\<CR>"
                endif
            endfunction

            " <CR> close popup and save indent or expand snippet
            imap <expr> <CR> CleverCr()
            " <C-h>, <BS>: close popup and delete backword char.
            inoremap <expr><BS> neocomplete#smart_close_popup()."\<C-h>"
            inoremap <expr><C-y> neocomplete#close_popup()
        " }

        " Enable omni completion.
        autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
        autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
        autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
        autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
        autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags
        autocmd FileType ruby setlocal omnifunc=rubycomplete#Complete
        autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc

        " Enable heavy omni completion.
        if !exists('g:neocomplete#sources#omni#input_patterns')
            let g:neocomplete#sources#omni#input_patterns = {}
        endif
        let g:neocomplete#sources#omni#input_patterns.php = '[^. \t]->\h\w*\|\h\w*::'
        let g:neocomplete#sources#omni#input_patterns.perl = '\h\w*->\h\w*\|\h\w*::'
        let g:neocomplete#sources#omni#input_patterns.c = '[^.[:digit:] *\t]\%(\.\|->\)'
        let g:neocomplete#sources#omni#input_patterns.cpp = '[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'
        let g:neocomplete#sources#omni#input_patterns.ruby = '[^. *\t]\.\h\w*\|\h\w*::'
    endif
    " }

    " Normal Vim omni-completion {
        " Enable omni-completion.
        autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
        autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
        autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
        autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
        autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags
        autocmd FileType ruby setlocal omnifunc=rubycomplete#Complete
        autocmd FileType haskell setlocal omnifunc=necoghc#omnifunc
    " }

    " Snippets {
        " Use honza's snippets.
        let g:neosnippet#snippets_directory='~/.vim/bundle/vim-snippets/snippets'

        " Enable neosnippet snipmate compatibility mode
        let g:neosnippet#enable_snipmate_compatibility = 1

        " Disable default snippets
        let g:neosnippet#disable_runtime_snippets = {
            \ '_' : 1,
        \ }

        " For snippet_complete marker.
        if has('conceal')
            set conceallevel=2 concealcursor=i
        endif

        " Disable the neosnippet preview candidate window
        " When enabled, there can be too much visual noise
        " especially when splits are used.
        " set completeopt-=preview
    " }

    " GitHub Flavored Markdown "{
        augroup markdown
            au!
            au BufNewFile,BufRead *.md,*.markdown setlocal filetype=ghmarkdown
        augroup END
    " }

    " Instant Mardown {
        " let g:instant_markdown_slow = 1  " Update only on save or timeout
        let g:instant_markdown_autostart = 0  " Autoupdate only on command
    " }

    " Gist {
        let g:gist_detect_filetype = 1
        let g:gist_open_browser_after_post = 1
        let g:gist_post_private = 1
        let g:gist_show_privates = 1
    " }
" }

" Ending settings {
    if filereadable(expand("~/.vimrc.local"))
        source ~/.vimrc.local
    endif

    set secure
" }
