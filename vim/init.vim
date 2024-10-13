" Modeline and Notes {{{
" vim: set foldlevel=0 foldmethod=marker spell formatoptions=jcrql:
" }}}

" Use this file to initialize things _before_ any other plugin is loaded.

" Initialization {{{
    " Define a global autogroup used through the entire vimrc
    augroup vimrc
        autocmd!
    augroup end

    " {{{ Providers
        " This needs to be done before loading plugins, as they might
        " require/load providers.

        " Disable non-required providers
        let g:loaded_python_provider = 0  " Disable Python 2 support.
        let g:loaded_ruby_provider = 0  "   Disable Ruby support.
        let g:loaded_node_provider = 0  "   Disable nodeJS support.
        let g:loaded_perl_provider = 0  "   Disable Perl support

        " Disable some of VIM standard plugins
        let g:loaded_2html_plugin = 1  " Disable tohtml.vim
        let g:loaded_tutor_mode_plugin = 1  " Disable vimtutor
        let g:loaded_vimballPlugin = 1  " Disable vimball
        let g:loaded_tarPlugin = 1  " Disable tar
        let g:loaded_getscriptPlugin = 1  " Disable getscript
        let g:loaded_zipPlugin = 1  " Disable zip
    " }}}

    packadd! matchit
" }}}

" General {{{
    " Sets how many lines of history VIM has to remember
    set history=10000 " Maximum value for history

    " Modeline in the first three lines
    set modeline
    set modelines=3

    " Mouse
    set mouse=a
    set mousehide               " Hide the mouse cursor while typing

    set updatetime=100          " ms to trigger the CursorHold/CursorHoldI events

    " With a map leader it's possible to do extra key combinations.
    " We set it here so it is effective for all `plugin/` files.
    let g:mapleader = "\<Space>"
    let g:maplocalleader = "\<Space>"
" }}}

" Text, lines, tab, indent and folding {{{
    set backspace=indent,eol,start                     " Backspace for dummies
    set whichwrap=b,s,h,l,<,>,[,]                      " Backspace and cursor keys wrap too

    " Line wrapping
    set wrap                                           " Visually wrap lines too long
    set textwidth=0 wrapmargin=0                       " Turn off physical line wrapping
    set breakindent                                    " Preserve indent of wrapped lines

    " Do not insert comment leader on 'o'
    " Needs an autocmd because different filetypes override this option
    " TODO: Tried disabling this, prefer filetype specific option?
    " autocmd vimrc FileType * setlocal formatoptions-=o
" }}}

" Plugin settings {{{
    " Investigate {{{
        " Use Dash on macOS (if available)
        let g:investigate_use_dash=1

        nnoremap <silent> K :call investigate#Investigate('n')<CR>
        vnoremap <silent> K :call investigate#Investigate('v')<CR>
    " }}}

    " lion {{{
        let g:lion_map_right = 'gR'  " Prevent conflict with vim.wiki
    " }}}

    " lists.vim {{{
        let g:lists_filetypes = ['md']
        let g:lists_todos = ['TODO', 'DONE']
    " }}}

    " wiki.vim {{{
        let g:wiki_root = '~/Documents/Notes'  " will be expanded later on
        let g:wiki_link_creation = {
                    \ 'md': {
                    \   'link_type': 'md',
                    \   'url_extension': '',
                    \ },
                    \}

        let g:wiki_select_method='fzf'

        " Disable unused mappings
        let g:wiki_mappings_global = {
                    \ '<plug>(wiki-index)' : '',
                    \ '<plug>(wiki-open)' : '',
                    \ '<plug>(wiki-reload)' : '',
                    \}

        let g:wiki_mappings_local = {
                    \ '<plug>(wiki-page-toc)' : '',
                    \ '<plug>(wiki-page-toc-local)' : '',
                    \ '<plug>(wiki-page-rename)' : '',
                    \ '<plug>(wiki-tag-list)' : '',
                    \ '<plug>(wiki-tag-reload)' : '',
                    \ '<plug>(wiki-tag-search)' : '',
                    \ '<plug>(wiki-link-next)' : '',
                    \ '<plug>(wiki-link-prev)' : '',
                    \ '<plug>(wiki-link-transform)' : '',
                    \ '<plug>(wiki-link-follow)' : '',
                    \ '<plug>(wiki-export)' : '',
                    \ '<plug>(wiki-rename)' : '',
                    \}

        function! TemplateWrapper(context) abort
            call aldur#wiki#template(a:context)
        endfunction

        function! TemplateMatcher(context) abort
            " Only match if within the wiki root
            return a:context.path =~ '^' . g:wiki_root
        endfunction

        " Catch-all template.
        let g:wiki_templates = [
            \ {
            \   'match_func': function('TemplateMatcher'),
            \   'source_func': function('TemplateWrapper')
            \ },
            \ ]

        " Configure `notational-fzf-vim`
        let g:nv_main_directory = g:wiki_root
        let g:nv_search_paths = [g:wiki_root, ]  " This is for backward-compatibility only
        let g:nv_create_note_window = 'edit'
        let g:nv_use_short_pathnames = 0
    " }}}
" }}}

" Ending settings {{{
    set secure
" }}}
