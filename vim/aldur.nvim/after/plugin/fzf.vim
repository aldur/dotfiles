if exists(':FZF') == 0
    finish
endif

let g:fzf_layout = { 'window': { 'width': 1.0, 'height': 0.4, 'relative': v:false, 'yoffset': 1.0, 'border': 'sharp' } }

" Override the Rg command so that it searches in the current project root
command! -bang -nargs=* RgProject call aldur#fzf#rg_project(<q-args>, <bang>0)

" Run `rg` in a given directory
command! -bang -nargs=? -complete=dir RgCd call aldur#fzf#rg_cd(<q-args>, <bang>0)

" Experimental own version of notational-fzf
command! -nargs=* -bang RGNotes call aldur#fzf#rg_notes(<q-args>, <bang>0)

if exists(':G')
    " Switch `git` branch through `fzf`
    command! -nargs=* -bang Gbranches call aldur#fzf#git_checkout_branch(<q-args>, <bang>0)
endif

nnoremap <silent> <leader><space> :<c-U>execute 'Files' aldur#find_root#find_root()<CR>
nnoremap <silent> <leader>a :Buffers<CR>
nnoremap <silent> <leader>r :RgProject<CR>
nnoremap <silent> <leader>tt :BTags<CR>
nnoremap <silent> <leader>T :Tags<CR>
nnoremap <silent> <leader>h :History<CR>
nnoremap <silent> <leader>H :Files ~<CR>
nnoremap <silent> <leader>: :History:<CR>

" NOTE this will be overwritten by LSP
nnoremap <silent> <leader>u :RgProject <C-r><C-w><CR>

if !empty($FZF_DEFAULT_COMMAND)
    inoremap <expr> <plug>(fzf-complete-path)      fzf#vim#complete#path($FZF_DEFAULT_COMMAND)
endif

if !empty($FZF_DEFAULT_COMMAND)
    inoremap <expr> <plug>(fzf-complete-file)      fzf#vim#complete#path($FZF_DEFAULT_COMMAND . ' --type f')
endif

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
