function! aldur#rm#rm_current() abort
    call aldur#auto_read_write#rm_from_oldfiles()
    let l:file = expand('%:p')
    bd!
    noautocmd execute 'silent !rm ' . l:file
endfunction
