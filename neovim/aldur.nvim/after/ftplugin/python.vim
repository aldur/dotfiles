let g:python_highlight_all = 1  " Enable all Python syntax highlights

" compiler python  " Sets makeprg=python3\ -t\ %
compiler pipenv  " Calls `compiler python` and sets makeprg=cd\ %:h\ &&\ pipenv\ run\ python\ %:t

setlocal formatoptions=crql

" Setup folds
setlocal foldmethod=expr
setlocal foldexpr=nvim_treesitter#foldexpr()

let b:undo_ftplugin = 'setlocal formatoptions< foldmethod< foldexpr<'
