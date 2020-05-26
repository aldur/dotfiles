if exists(':FZF') == 0
    finish
endif

let g:fzf_layout = { 'down': '~40%' }
function! FZFRoot() abort
    try
        " If possible, execut FZF from the current project root.
        " We're using gutentags#get_project_root for the task.
        let l:root = gutentags#get_project_root(expand('%:p:h', 1))
    catch
        let l:root = expand('%:p:h', 1)
    endtry

    " If it's a terminal, then we default to cwd
    if l:root =~# 'term://'
        let l:root = getcwd()
    endif

    return l:root
endfunction

" Hide statusbar while FZF is on.
autocmd vimrc FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd vimrc BufLeave <buffer> set laststatus=2 noshowmode ruler

" Override the Rg command so that it searches in the current root
command! -bang -nargs=* LocalRg
            \ call fzf#vim#grep("rg --column --line-number --no-heading --color=always --smart-case ".shellescape(<q-args>)." ".FZFRoot(), 1, fzf#vim#with_preview(), <bang>0)

nnoremap <silent> <leader><space> :<c-U>execute 'Files' FZFRoot()<CR>
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
