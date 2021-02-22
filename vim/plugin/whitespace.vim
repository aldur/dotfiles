autocmd vimrc FileType c,cpp,java,php,javascript,markdown,wiki,python,twig,xml,yaml,vim,lua
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#strip_trailing()

autocmd vimrc FileType markdown,wiki
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#retab()
