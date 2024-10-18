function aldur#auto_read_write#write_gently() abort
    if &previewwindow || &buftype ==# 'nofile' || &buftype ==# 'nowrite'
        return
    end

    silent! w
endf

" Add the current file path to v:oldfiles
function aldur#auto_read_write#add_to_oldfiles() abort
    let l:current_path = expand('%:p')

    " On failure, `expand` returns an empty string
    if l:current_path ==# ''
        return
    endif

    if index(v:oldfiles, l:current_path) == -1
        let v:oldfiles += [l:current_path]
        wshada
    endif
endf
