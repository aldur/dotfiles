autocmd vimrc FileType c,cpp,java,php,javascript,markdown,python,twig,xml,yaml,vim,lua
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#strip_trailing()

autocmd vimrc FileType markdown
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#retab()
