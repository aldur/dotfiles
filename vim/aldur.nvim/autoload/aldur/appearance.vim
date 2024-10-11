function aldur#appearance#setlaststatus() abort
    if has('nvim')
        set laststatus=3 " Set global statusbar
    else
        set laststatus=2 " Always show the statusbar
    endif
endf
