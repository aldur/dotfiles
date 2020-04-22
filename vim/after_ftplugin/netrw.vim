if len(g:netrw_list_hide) == 0
    " Lazily populate `netrw_list_hide` first time we load a netrw buffer.
    " Removes the `*.o` pattern as, somehow, hides more than it should.
    let g:netrw_list_hide = substitute(netrw_gitignore#Hide(), ',.\*\\.o', '', '')  " Hide git-ignored files
endif
