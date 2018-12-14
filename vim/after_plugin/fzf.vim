if exists(':FZF') == 0
    finish
endif

let g:fzf_layout = { 'down': '~40%' }
function! s:FZFFiles() abort
    try
        " If possible, launch FZF from the current project root.
        " We're using gutentags#get_project_root for the task.
        execute 'Files' gutentags#get_project_root(expand('%:p:h', 1))
    catch
        execute 'Files' expand('%:p:h', 1)
    endtry
endfunction

autocmd vimrc FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd vimrc BufLeave <buffer> set laststatus=2 showmode ruler

nnoremap <silent> <leader><space> :call <SID>FZFFiles()<CR>
nnoremap <silent> <leader>a :Buffers<CR>
nnoremap <silent> <leader>A :Ag<CR>
nnoremap <silent> <leader>tt :BTags<CR>
nnoremap <silent> <leader>tT :Tags<CR>
nnoremap <silent> <leader>? :History<CR>
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
