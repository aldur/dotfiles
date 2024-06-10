compiler poetry-beancount

setlocal formatprg=bean-format

setlocal comments=b:;
setlocal commentstring=;\ %s

setlocal iskeyword+=:
setlocal iskeyword+=-

setlocal formatoptions+=r
setlocal formatoptions+=o

command -buffer ReloadCompletions w | lua require'plugins/beancount'.reload_beancount_completions()
