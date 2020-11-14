if exists(':FZF') == 0
    finish
endif

let g:fzf_layout = { 'down': '~40%' }

" Hide statusbar while FZF is on.
autocmd vimrc FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd vimrc BufLeave <buffer> set laststatus=2 noshowmode ruler

" Override the Rg command so that it searches in the current root
" Here we don't need smart case because we set it in `~/.ripgreprc`.
"
" https://github.com/junegunn/fzf.vim/issues/346#issuecomment-288483704
" {'options': '--delimiter : --nth 4..'} will make `rg` search file contents
" only, not names.
"
" The `dir` option specify the search directory, source:
" https://github.com/junegunn/fzf.vim/issues/837
"
" If you are wondering how this works, in short when you trigger this without
" any arguments `rg` gets called without any arguments as well and lists all
" file lines. Then, `fzf` does the filtering.
command! -bang -nargs=* RgProject
            \ call fzf#vim#grep("rg --column --line-number --no-heading --color=always ".shellescape(<q-args>), 1, fzf#vim#with_preview({'options': '--delimiter : --nth 4..', 'dir': aldur#find_root#find_root()}), <bang>0)

" Run `rg` in a given directory
" Here we pass an empty pattern to `rg` to match everything.
command! -bang -nargs=? -complete=dir RgCd
            \ call fzf#vim#grep("rg --column --line-number --no-heading --color=always ''", 1, fzf#vim#with_preview({'options': '--delimiter : --nth 4..', 'dir': shellescape(<q-args)}), <bang>0)

nnoremap <silent> <leader><space> :<c-U>execute 'Files' aldur#find_root#find_root()<CR>
nnoremap <silent> <leader>a :Buffers<CR>
nnoremap <silent> <leader>g :RgProject<CR>
" nnoremap <silent> <leader>G :Rg<CR>
nnoremap <silent> <leader>tt :BTags<CR>
nnoremap <silent> <leader>tT :Tags<CR>
nnoremap <silent> <leader>h :History<CR>
nnoremap <silent> <leader>H :Files ~<CR>
nnoremap <silent> <leader>: :History:<CR>

imap <silent> <c-x><c-f> <plug>(fzf-complete-path)
imap <silent> <c-x><c-k> <plug>(fzf-complete-word)

let g:fzf_colors = {
            \ 'fg':      ['fg', 'Normal'],
            \ 'bg':      ['bg', 'Normal'],
            \ 'hl':      ['fg', 'Comment'],
            \ 'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
            \ 'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
            \ 'hl+':     ['fg', 'Statement'],
            \ 'info':    ['fg', 'PreProc'],
            \ 'border':  ['fg', 'Ignore'],
            \ 'prompt':  ['fg', 'Conditional'],
            \ 'pointer': ['fg', 'Exception'],
            \ 'marker':  ['fg', 'Keyword'],
            \ 'spinner': ['fg', 'Label'],
            \ 'header':  ['fg', 'Comment'] }
