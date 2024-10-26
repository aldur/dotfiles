function! aldur#auto_read_write#write_gently() abort
    if &previewwindow || &buftype ==# 'nofile' || &buftype ==# 'nowrite'
        return
    end

    silent! w
endf

" Add the current file path to v:oldfiles
function! aldur#auto_read_write#add_to_oldfiles() abort
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

function! aldur#auto_read_write#rm_from_oldfiles() abort
    " NOTE: This might fail one some occasions where
    " eg editing /tmp/test
    " while the underlying file is /private/tmp/test
    let l:current_path = expand('%:p')

    " On failure, `expand` returns an empty string
    if l:current_path ==# ''
        return
    endif

    let l:index = index(v:oldfiles, l:current_path)
    if l:index == -1
        " Something went wrong, this should be here.
        echo "Current path was not found in `v:oldfiles`."
        return
    endif

    call remove(v:oldfiles, l:index)
    wshada
endf
