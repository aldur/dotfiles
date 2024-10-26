compiler beancount

setlocal formatprg=bean-format

setlocal comments=b:;
setlocal commentstring=;\ %s

setlocal iskeyword+=:
setlocal iskeyword+=-

setlocal formatoptions+=r
setlocal formatoptions+=o

let b:undo_ftplugin = "setlocal iskeyword< formatprg< comments< commentstring< formatoptions<"

command -buffer ReloadBeancountCompletions w | lua require'aldur.beancount'.reload_beancount_completions()
