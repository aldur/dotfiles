" Set an abbreviation that only works at beginning of command line.
function aldur#abbr#cnoreabbrev(lhs, rhs) abort
    execute "cnoreabbrev <expr> " . a:lhs . " (getcmdtype() ==# ':' && getcmdline() ==# '" . a:lhs . "' )  ?  '" . a:rhs . "' : '" . a:lhs . "'"
endfunction
