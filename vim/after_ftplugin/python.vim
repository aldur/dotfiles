let g:python_highlight_all = 1  " Enable all Python syntax highlights

" compiler python  " Sets makeprg=python3\ -t\ %
compiler pipenv  " Calls `compiler python` and sets makeprg=cd\ %:h\ &&\ pipenv\ run\ python\ %:t

setlocal formatoptions+=r

" Setup folds
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
