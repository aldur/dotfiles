scriptencoding utf-8

let g:ale_lint_on_enter = 1
let g:ale_lint_on_save = 1
let g:ale_lint_on_filetype_changed = 1

let g:ale_echo_msg_error_str = 'E'
let g:ale_echo_msg_warning_str = 'W'
let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'

let g:airline#extensions#ale#enabled = 0  " Disable airline integration
autocmd vimrc User ALELintPost call lightline#update()

" Better warning sign.
let g:ale_sign_warning = '•'
let g:ale_sign_error = '✘'
highlight ALEErrorSign ctermbg=NONE ctermfg=red
highlight ALEWarningSign ctermbg=NONE ctermfg=yellow

function! ALEFixGently() abort
    " Preparation: save cursor position
    " (last search is automatically saved because inside a function)
    let l:save = winsaveview()

    " Do the business.
    ALEFix

    " Clean up: restore cursor position.
    call winrestview(l:save)
endfunction
nnoremap <leader>f :<C-u>silent call ALEFixGently()<CR>

" This is macOS specific, but for the time being it's fine since it's the only
" OS we use this in :)
let g:ale_cpp_ccls_init_options = {
            \   'cache': {
            \       'directory': '/tmp/ccls/cache'
            \   },
            \   'clang': {
            \        'extraArgs': [
            \               '-isystem', '/Library/Developer/CommandLineTools/usr/include/c++/v1',
            \               '-isystem', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include'
            \        ],
            \   },
            \ }
