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
command! -bang -nargs=* RgProject
            \ call fzf#vim#grep("rg --column --line-number --no-heading --color=always ".shellescape(<q-args>)." ".aldur#find_root#find_root(), 1, fzf#vim#with_preview({'options': '--delimiter : --nth 4..'}), <bang>0)

" Run `rg` in a given directory
" Here we pass an empty pattern to `rg` to match everything.
command! -bang -nargs=? -complete=dir RgCd
            \ call fzf#vim#grep("rg --column --line-number --no-heading --color=always '' ".shellescape(<q-args>), 1, fzf#vim#with_preview({'options': '--delimiter : --nth 4..'}), <bang>0)

nnoremap <silent> <leader><space> :<c-U>execute 'Files' aldur#find_root#find_root()<CR>
nnoremap <silent> <leader>a :Buffers<CR>
nnoremap <silent> <leader>g :LocalRg<CR>
nnoremap <silent> <leader>G :Rg<CR>
nnoremap <silent> <leader>tt :BTags<CR>
nnoremap <silent> <leader>tT :Tags<CR>
nnoremap <silent> <leader>h :History<CR>
nnoremap <silent> <leader>H :Files ~<CR>
nnoremap <silent> <leader>: :History:<CR>

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
