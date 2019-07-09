scriptencoding utf-8

" Run Neomake on save / WinEnter
call neomake#configure#automake('rw')

function! s:NeomakeDidFinish() abort
    " Update lightline
    call lightline#update()
    " Close loclist if no errors
    if get(neomake#statusline#LoclistCounts(), 'E', 0) == 0 &&
                \ get(neomake#statusline#LoclistCounts(), 'W', 0) == 0 &&
                \ get(neomake#statusline#LoclistCounts(), 'I', 0) == 0
        lclose
    endif
endfunction
autocmd vimrc User NeomakeFinished call <SID>NeomakeDidFinish()
let g:airline#extensions#neomake#enabled = 0  " Disable airline integration

" Better warning sign.
let g:neomake_warning_sign = {'text': '•', 'texthl': 'NeomakeWarningSign'}

" tex-specific makers
let g:neomake_tex_enabled_makers = ['chktex', 'lacheck', 'proselint']

