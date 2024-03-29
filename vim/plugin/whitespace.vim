autocmd vimrc FileType c,cpp,java,php,javascript,markdown,wiki,python,twig,xml,yaml,vim,lua,algorand-teal,solidity,beancount
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#strip_trailing()

autocmd vimrc FileType markdown,wiki
            \ autocmd vimrc BufWritePre <buffer> call aldur#whitespace#retab()
