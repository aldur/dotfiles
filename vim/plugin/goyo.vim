" For some reaosns Goyo doesn't reset line numbers on exit.
function! s:goyo_leave()
    set number
    set relativenumber
endfunction

autocmd! User GoyoLeave nested call <SID>goyo_leave()
