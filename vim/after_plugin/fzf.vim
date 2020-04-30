if exists(':FZF') == 0
    finish
endif

let g:fzf_layout = { 'down': '~40%' }
function! FZFRoot() abort
    try
        " If possible, execut FZF from the current project root.
        " We're using gutentags#get_project_root for the task.
        return gutentags#get_project_root(expand('%:p:h', 1))
    catch
        return expand('%:p:h', 1)
    endtry
endfunction

" Hide statusbar while FZF is on.
autocmd vimrc FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd vimrc BufLeave <buffer> set laststatus=2 noshowmode ruler

nnoremap <silent> <leader><space> :<c-U>execute 'Files' FZFRoot()<CR>
nnoremap <silent> <leader>a :Buffers<CR>
nnoremap <silent> <leader>g :Ag<CR>
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
