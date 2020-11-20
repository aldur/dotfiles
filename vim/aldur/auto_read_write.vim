function aldur#auto_read_write#write_gently() abort
    if &previewwindow || &buftype ==# 'nofile' || &buftype ==# 'nowrite'
        return
    end

    silent! w
endf
