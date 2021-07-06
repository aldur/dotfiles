if !exists(':ALEInfo')
    finish
endif

scriptencoding utf-8

let g:ale_lint_on_enter = 1
let g:ale_lint_on_save = 1
let g:ale_lint_on_filetype_changed = 1

if has('nvim')
    let g:ale_hover_cursor = 0
    let g:ale_hover_to_preview = 1
    let g:ale_floating_preview = 1
    let g:ale_floating_window_border = ['│', '─', '╭', '╮', '╯', '╰']
endif

" Lint when changing window
autocmd vimrc WinLeave * :ALELint

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

nnoremap <silent> <leader>f :<C-u>silent call aldur#ale#fix_gently()<CR>

" Mnemonic for 'usages'
nnoremap <silent> <leader>u :<C-u>ALEFindReferences -relative<CR>

" Show hover. You can use `<C-y>` to close the autocomplete popup
inoremap <silent> <C-x><C-i> <C-o>:<C-u>ALEHover<CR>
autocmd vimrc CursorHoldI * :ALEHover

" Reload ALE after configuring it.
" ALEDisable | ALEEnable
