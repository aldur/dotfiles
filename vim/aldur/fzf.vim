" :h fzf-vim-example-advanced-ripgrep-integration
function! aldur#fzf#rg_notes(query, fullscreen) abort
    let l:initial_command = "rg --column --line-number --no-heading --color=always ''"
    let l:spec = {'options': '--delimiter : --nth 4..', 'dir': g:wiki_root}
    call fzf#vim#grep(l:initial_command, 1, fzf#vim#with_preview(l:spec), a:fullscreen)
endfunction
