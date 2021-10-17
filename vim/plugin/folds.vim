set fillchars+=fold:\  " Note that there's a space here.

" https://www.reddit.com/r/neovim/comments/psl8rq/sexy_folds/
" set foldtext=substitute(getline(v:foldstart),'\\t',repeat('\ ',&tabstop),'g').'...'.trim(getline(v:foldend))
set foldtext=substitute(getline(v:foldstart),'\\t',repeat('\ ',&tabstop),'g').'\ ...'

set foldnestmax=2
set foldminlines=3

" set foldcolumn=auto

nnoremap <expr> 4 ToggleFolds()
xnoremap <expr> 4 ToggleFolds()
nnoremap <expr> 44 ToggleFolds() .. '_'

function ToggleFolds(type='') abort
    " Operator to toggle folds.
    if a:type == ''
        set operatorfunc=ToggleFolds
        return 'g@'
    endif

    let sel_save = &selection
    let cb_save = &clipboard
    let visual_marks_save = [getpos("'<"), getpos("'>")]

    try
        set clipboard= selection=inclusive
        let commands = #{line: "'[V']", char: "`[v`]", block: "`[\<c-v>`]"}
        silent! call aldur#stay#stay('noautocmd keepjumps normal! ' .. get(commands, a:type, '') .. 'za')
        execute "normal! \<Esc>"
    finally
        call setpos("'<", visual_marks_save[0])
        call setpos("'>", visual_marks_save[1])
        let &clipboard = cb_save
        let &selection = sel_save
    endtry
endfunction

