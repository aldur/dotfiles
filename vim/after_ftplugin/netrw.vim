if len(g:netrw_list_hide) == 0
    " Lazily populate `netrw_list_hide` first time we load a netrw buffer.
    let g:netrw_list_hide = netrw_gitignore#Hide()  " Hide git-ignored files
endif 
