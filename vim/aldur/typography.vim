function aldur#typography#remove_smart_characters() range abort
    let l:map = {'’': "'", '“': '"', '”': '"', }
    for [l:next_key, l:next_val] in items(l:map)
        for l:line_number in range(a:firstline, a:lastline)
            let l:current_line = getline(line_number)
            let l:current_line_commented = substitute(l:current_line, l:next_key, l:next_val, "")
            call setline(l:line_number, l:current_line_commented)
        endfor
    endfor
endf
