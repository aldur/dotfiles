function! aldur#rm#rm_current() abort
    call aldur#auto_read_write#rm_from_oldfiles()
    execute '! rm %'
    bd!
endfunction
